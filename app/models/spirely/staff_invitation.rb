module Spirely
  # Grants staff/admin access to a church — deliberately its own model
  # rather than reusing Spirely::Invitation, which is fundamentally
  # family-shaped (belongs_to :family, mandatory). A staff invite has
  # nothing to do with any Family/Guardian record at all — same
  # token/expiry/single-use mechanics as the family invite flow, kept
  # separate to avoid coupling an unrelated concept into that model.
  class StaffInvitation < ApplicationRecord
    belongs_to :church

    before_validation :generate_token, on: :create
    before_validation :set_expiry, on: :create

    validates :token, presence: true, uniqueness: true
    validate :email_or_phone_present

    scope :active, -> { where(accepted_at: nil).where("expires_at > ?", Time.current) }

    def self.find_active(token)
      active.find_by(token: token)
    end

    # Always grants at least "admin" — never "owner", which stays reserved
    # for whoever originally provisioned the church (billing/deprovisioning
    # significance an invite-granted staff member shouldn't casually get).
    #
    # Deliberately NOT find_or_create_by! — that only sets attributes in
    # its block on a brand-new record, so it would silently no-op for
    # someone who already has a Membership at this church (e.g. an
    # existing "family"-role parent/volunteer being invited onto staff,
    # a real case: real production user Danielle Robinett). Explicitly
    # upgrades an existing lesser-role Membership to "admin"; leaves an
    # existing "owner" or "admin" Membership alone rather than downgrading
    # or no-op-ing past it.
    def accept!(account_id)
      membership = Membership.find_or_initialize_by(account_id: account_id, church_id: church_id)
      membership.role = "admin" unless membership.persisted? && membership.role.in?(%w[admin owner])
      membership.save!
      update!(accepted_at: Time.current)
    end

    def expired?
      expires_at <= Time.current
    end

    def accepted?
      accepted_at.present?
    end

    def invite_url
      "https://#{church.primary_hostname}/staff-invite/#{token}"
    end

    private

    def generate_token
      self.token ||= SecureRandom.urlsafe_base64(24)
    end

    def set_expiry
      self.expires_at ||= 7.days.from_now
    end

    def email_or_phone_present
      return if invited_email.present? || invited_phone.present?
      errors.add(:base, "An email or phone number is required")
    end
  end
end
