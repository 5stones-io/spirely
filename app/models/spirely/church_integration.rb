module Spirely
  class ChurchIntegration < ApplicationRecord
    TOKEN_TYPES = %w[personal oauth].freeze

    belongs_to :church

    validates :token_type, presence: true, inclusion: { in: TOKEN_TYPES }

    # token_type is which auth method is *currently active* for this
    # church's PCO calls (PcoClient branches on it) — a church can have
    # both an OAuth app and a PAT saved at once (each Settings card saves
    # independently), but only one is ever actually used, whichever this
    # says. Saving either card's credentials flips this (see
    # Admin::ConfigController#update).
    def personal_token?
      token_type == "personal"
    end

    # "Connected," unlike OAuth, has no separate handshake for a PAT — it
    # authenticates directly on every API call (HTTP Basic, app_id:secret),
    # so saving valid-looking credentials *is* being connected. Whether
    # they're actually valid is only known the first time a real API call
    # is made; this mirrors the same "configured, not verified" honesty
    # pco_app_configured? already has for OAuth.
    def pco_connected?
      if personal_token?
        pco_pat_configured?
      else
        self[:access_token].present?
      end
    end

    def pco_app_configured?
      if personal_token?
        pco_pat_configured?
      else
        pco_client_id.present? && self[:pco_client_secret].present?
      end
    end

    def pco_pat_configured?
      pco_pat_app_id.present? && self[:pco_pat_secret].present?
    end

    def pco_pat_secret
      Spirely::Encryption.decrypt(self[:pco_pat_secret])
    end

    def pco_pat_secret=(value)
      self[:pco_pat_secret] = Spirely::Encryption.encrypt(value)
    end

    before_save :reset_twilio_verification_if_credentials_changed

    def twilio_configured?
      twilio_account_sid.present? && self[:twilio_auth_token].present? && twilio_from_number.present?
    end

    # Credentials being present only means Twilio *accepted* the API call
    # — not that a real phone actually received it (see the A2P 10DLC
    # carrier-filtering gap documented in spirely-cloud's CLAUDE.md,
    # confirmed 2026-08-09 against a real send that Twilio reported
    # success on but never reached the destination phone).
    # `twilio_verified?` is the stronger claim: an admin sent themselves a
    # real test code and typed it back, confirming an actual phone
    # received it. `InviteSender` gates real sends on this, not
    # `twilio_configured?`.
    def twilio_verified?
      twilio_verified_at.present?
    end

    def twilio_auth_token
      Spirely::Encryption.decrypt(self[:twilio_auth_token])
    end

    def twilio_auth_token=(value)
      self[:twilio_auth_token] = Spirely::Encryption.encrypt(value)
    end

    def token_expired?
      expires_at.present? && expires_at <= Time.current
    end

    def pco_client_secret
      Spirely::Encryption.decrypt(self[:pco_client_secret])
    end

    def pco_client_secret=(value)
      self[:pco_client_secret] = Spirely::Encryption.encrypt(value)
    end

    def access_token
      Spirely::Encryption.decrypt(self[:access_token])
    end

    def access_token=(value)
      self[:access_token] = Spirely::Encryption.encrypt(value)
    end

    def refresh_token
      Spirely::Encryption.decrypt(self[:refresh_token])
    end

    def refresh_token=(value)
      self[:refresh_token] = Spirely::Encryption.encrypt(value)
    end

    def update_tokens!(access:, refresh:, expires_in: nil)
      self.access_token  = access
      self.refresh_token = refresh
      self.expires_at    = expires_in ? Time.current + expires_in.seconds : nil
      save!
    end

    private

    # A verified claim only means anything for the exact credentials it
    # was confirmed against — swapping the account, token, or from_number
    # on an already-saved integration invalidates it, same as re-entering
    # PCO credentials would need a fresh OAuth handshake. Skipped on the
    # record's first-ever save (persisted? false) — there's nothing to
    # invalidate yet, and without this guard, saving twilio_verified_at
    # for the first time in the same create call as the credentials
    # themselves (e.g. a rake task backfill, or a factory in specs) would
    # immediately null itself back out, since every attribute "changes"
    # from nil on a brand-new record.
    def reset_twilio_verification_if_credentials_changed
      return unless persisted?
      return unless will_save_change_to_twilio_account_sid? ||
                    will_save_change_to_twilio_auth_token? ||
                    will_save_change_to_twilio_from_number?

      self.twilio_verified_at = nil
    end
  end
end
