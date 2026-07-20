module Spirely
  class ChurchIntegration < ApplicationRecord
    TOKEN_TYPES = %w[personal oauth].freeze

    validates :token_type, presence: true, inclusion: { in: TOKEN_TYPES }

    def self.current
      first_or_initialize(token_type: "oauth")
    end

    def pco_connected?
      self[:access_token].present?
    end

    def token_expired?
      expires_at.present? && expires_at <= Time.current
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
  end
end
