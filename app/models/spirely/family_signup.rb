module Spirely
  # A new family asking for an account from the church's site (5ST-85).
  # Created when someone we don't have on file uses Create Account
  # (Spirely::AccountRequest); the emailed link (#invite_url) opens a form
  # where they fill in #details, and staff approve or decline it.
  #
  #   started → submitted → approved | declined
  #
  # details: { "first_name", "last_name", "address",
  #            "children" => [{ "first_name", "last_name", "birthdate", "allergies" }] }
  class FamilySignup < ApplicationRecord
    class NotPending < StandardError; end

    STATUSES = %w[started submitted approved declined].freeze
    MAX_CHILDREN = 12
    EMAIL = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

    belongs_to :church
    belongs_to :matched_family, class_name: "Spirely::Family", optional: true
    belongs_to :family, class_name: "Spirely::Family", optional: true
    belongs_to :reviewed_by_account, class_name: "::Account", optional: true

    scope :waiting, -> { where(status: "submitted") }

    validates :status, inclusion: { in: STATUSES }
    validates :phone, format: { with: /\A\d{10}\z/, message: "must be a 10-digit phone number" }
    validates :email, format: { with: EMAIL, message: "doesn't look like an email address" }
    validate :details_complete, if: -> { status == "submitted" }

    before_validation :normalize_contact
    before_create :generate_token

    # The last 10 digits, so "(555) 201-3344" and "+1 555 201 3344" match.
    def self.normalize_phone(phone)
      digits = phone.to_s.gsub(/\D/, "")
      digits = digits[1..] if digits.length == 11 && digits.start_with?("1")
      digits
    end

    def invite_url
      "https://#{church.primary_hostname}/join/#{token}"
    end

    def expired?
      expires_at <= Time.current
    end

    def submit!(raw)
      update!(details: clean_details(raw), status: "submitted", submitted_at: Time.current)
    rescue ActiveRecord::RecordInvalid
      restore_attributes
      raise
    end

    # Creates the family and its kids, then sends the normal invite (email,
    # and text once the church's texting is verified) and, when Planning
    # Center is connected, adds them there, same as Quick Add.
    def approve!(by:)
      created = with_lock do
        raise NotPending unless status == "submitted"

        family = church.families.create!(
          family_name: "#{details["last_name"]} Family",
          primary_contact_first_name: details["first_name"], primary_contact_last_name: details["last_name"],
          phone: phone, email: email, address: details["address"].presence,
        )
        Array(details["children"]).each do |c|
          family.children.create!(
            first_name: c["first_name"], last_name: c["last_name"].presence || details["last_name"],
            birthdate: c["birthdate"].presence, allergy_notes: c["allergies"].presence,
          )
        end
        update!(status: "approved", family: family, reviewed_by_account: by, reviewed_at: Time.current)
        family
      end

      invitation = created.invitations.create!
      Spirely::InviteSender.call(church: church, first_name: created.primary_contact_first_name,
                                 phone: created.phone, email: created.email, invitation: invitation)
      Spirely::PcoCreatePersonJob.perform_later(created.id) if church.church_integration&.pco_connected?
      created
    end

    def decline!(by:)
      with_lock do
        raise NotPending unless status == "submitted"
        update!(status: "declined", reviewed_by_account: by, reviewed_at: Time.current)
      end
    end

    private

    def normalize_contact
      self.phone = self.class.normalize_phone(phone)
      self.email = email.to_s.strip.downcase
    end

    def generate_token
      self.token = SecureRandom.urlsafe_base64(24)
      self.expires_at ||= 7.days.from_now
    end

    def clean_details(raw)
      raw = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
      raw = raw.deep_stringify_keys
      text = ->(v, max = 200) { v.is_a?(String) ? v.strip[0, max] : "" }
      children = Array(raw["children"]).first(MAX_CHILDREN).filter_map do |c|
        next unless c.is_a?(Hash) || c.respond_to?(:to_unsafe_h)
        c = (c.respond_to?(:to_unsafe_h) ? c.to_unsafe_h : c).stringify_keys
        next if text.(c["first_name"]).blank?
        { "first_name" => text.(c["first_name"]), "last_name" => text.(c["last_name"]),
          "birthdate" => parse_date(c["birthdate"]), "allergies" => text.(c["allergies"], 1000) }
      end
      { "first_name" => text.(raw["first_name"]), "last_name" => text.(raw["last_name"]),
        "address" => text.(raw["address"], 500), "children" => children }
    end

    def parse_date(value)
      date = Date.iso8601(value.to_s)
      date.between?(25.years.ago.to_date, Date.current) ? date.iso8601 : nil
    rescue Date::Error
      nil
    end

    def details_complete
      errors.add(:base, "Add your first and last name.") if details["first_name"].blank? || details["last_name"].blank?
      errors.add(:base, "Add at least one child.") if Array(details["children"]).empty?
    end
  end
end
