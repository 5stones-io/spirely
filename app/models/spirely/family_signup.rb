module Spirely
  # Someone asking for an account from the church's site (5ST-85). Create
  # Account (Spirely::AccountRequest) emails a "confirm your email" link
  # (#invite_url) to whatever was typed, whoever they are. Opening it
  # (#confirm!) is the first time we look them up, by the now-confirmed
  # email:
  #
  #   on file, no account  → invited (their invite, made here)
  #   on file with one     → has_account (go sign in)
  #   not on file          → started, with the new-family form; they fill
  #                          in #details and staff approve or decline it:
  #                          started → submitted → approved | declined
  #
  # The phone isn't confirmed, so a family with the same phone is only
  # noted for staff (matched_family), never handed over.
  #
  # details: { "first_name", "last_name", "address",
  #            "children" => [{ "first_name", "last_name", "birthdate", "allergies" }] }
  class FamilySignup < ApplicationRecord
    class NotPending < StandardError; end

    STATUSES = %w[started invited has_account submitted approved declined].freeze
    MAX_CHILDREN = 12
    EMAIL = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

    belongs_to :church
    belongs_to :matched_family, class_name: "Spirely::Family", optional: true
    belongs_to :family, class_name: "Spirely::Family", optional: true
    belongs_to :invitation, class_name: "Spirely::Invitation", optional: true
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

    # When they open the emailed link. Runs once; later visits see what the
    # first one found.
    def confirm!
      with_lock do
        next if status != "started" || email_confirmed_at || expired?

        self.email_confirmed_at = Time.current
        person = on_file_by_email
        if person.nil?
          self.matched_family = family_with_same_phone
        elsif person.account_id
          self.status = "has_account"
          self.family = family_of(person)
        else
          self.status = "invited"
          self.family = family_of(person)
          self.invitation = invite(person)
        end
        save!
      end
      self
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

    PHONE_DIGITS = "right(regexp_replace(coalesce(%s, ''), '\\D', '', 'g'), 10)"

    def on_file_by_email
      church.families.where("lower(email) = ?", email).order(:id).first ||
        Spirely::Guardian.joins(:family).where(spirely_families: { church_id: church_id })
                         .where("lower(spirely_guardians.email) = ?", email).order(:id).first
    end

    def family_with_same_phone
      church.families.where("#{format(PHONE_DIGITS, "phone")} = ?", phone).order(:id).first ||
        Spirely::Guardian.joins(:family).where(spirely_families: { church_id: church_id })
                         .where("#{format(PHONE_DIGITS, "spirely_guardians.phone")} = ?", phone)
                         .order(:id).first&.family
    end

    def family_of(person) = person.is_a?(Spirely::Guardian) ? person.family : person

    # Same invite staff send: a guardian on file gets one of their own.
    def invite(person)
      family = family_of(person)
      guardian = person.is_a?(Spirely::Guardian) ? person : nil
      family.invitations.where(guardian: guardian, accepted_at: nil).update_all(expires_at: Time.current)
      family.invitations.create!(guardian: guardian)
    end

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
      errors.add(:base, "Confirm your email first.") if email_confirmed_at.nil?
      errors.add(:base, "Add your first and last name.") if details["first_name"].blank? || details["last_name"].blank?
      errors.add(:base, "Add at least one child.") if Array(details["children"]).empty?
    end
  end
end
