module Spirely
  class Invitation < ApplicationRecord
    belongs_to :church
    belongs_to :family
    # Present only for a guardian-scoped invite (multi-account family
    # access) — nil means this is the original family-primary invite,
    # which links `family.account_id` on accept. `guardian` present means
    # it links that specific Guardian's own `account_id` instead, so a
    # second parent can independently sign in without displacing the
    # first — see #accept!.
    belongs_to :guardian, optional: true

    before_validation :inherit_church_from_family
    before_create :generate_token

    scope :active, -> { where(accepted_at: nil).where("expires_at > ?", Time.current) }

    def self.find_active(token)
      active.find_by(token: token)
    end

    # Links the account to the family (or, for a guardian-scoped invite,
    # to that specific Guardian) AND establishes (or reuses) the
    # family-role Membership for this church — Membership can't be the sole
    # source of a Family's tenant scope (a Family can exist pre-invitation,
    # imported from PCO or admin-created, before any Membership exists), so
    # this is the one place the two are kept in sync. Each guardian's own
    # Membership row is independent (Membership is account-scoped, not
    # family-scoped), so multiple accounts on the same family need no
    # further change there.
    def accept!(account_id)
      if guardian
        guardian.update!(account_id: account_id)
      else
        family.update!(account_id: account_id)
      end
      Membership.find_or_create_by!(account_id: account_id, church_id: family.church_id) do |m|
        m.role = "family"
      end
      update!(accepted_at: Time.current)
    end

    def expired?
      expires_at <= Time.current
    end

    def accepted?
      accepted_at.present?
    end

    def invite_url
      "https://#{family.church.primary_hostname}/invite/#{token}"
    end

    private

    def inherit_church_from_family
      self.church_id ||= family&.church_id
    end

    def generate_token
      self.token      = SecureRandom.urlsafe_base64(24)
      self.expires_at = 7.days.from_now
    end
  end
end
