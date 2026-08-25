require "httparty"

module Spirely
  # Thin wrapper around Ory Hydra's admin API (login/consent flow). Reused
  # near-verbatim from self-hosted spirely — Hydra's admin API operates on
  # cross-tenant OAuth2 concepts (clients, login/consent challenges) by
  # nature, so it needs no tenant-awareness of its own.
  class HydraClient
    include HTTParty

    def initialize
      self.class.base_uri Spirely.configuration.hydra_admin_url
    end

    def get_login_request(challenge)
      request(:get, "/admin/oauth2/auth/requests/login", query: { login_challenge: challenge })
    end

    def accept_login_request(challenge, subject:, remember: false, remember_for: 0)
      request(:put, "/admin/oauth2/auth/requests/login/accept",
        query: { login_challenge: challenge },
        body: {
          subject:      subject,
          remember:     remember,
          remember_for: remember_for,
        }.to_json)
    end

    def reject_login_request(challenge, error: "access_denied", error_description: "Login was denied")
      request(:put, "/admin/oauth2/auth/requests/login/reject",
        query: { login_challenge: challenge },
        body: { error: error, error_description: error_description }.to_json)
    end

    def get_consent_request(challenge)
      request(:get, "/admin/oauth2/auth/requests/consent", query: { consent_challenge: challenge })
    end

    def accept_consent_request(challenge, grant_scope:, remember: false, remember_for: 0)
      request(:put, "/admin/oauth2/auth/requests/consent/accept",
        query: { consent_challenge: challenge },
        body: {
          grant_scope:  grant_scope,
          remember:     remember,
          remember_for: remember_for,
        }.to_json)
    end

    def reject_consent_request(challenge, error: "access_denied", error_description: "Consent was denied")
      request(:put, "/admin/oauth2/auth/requests/consent/reject",
        query: { consent_challenge: challenge },
        body: { error: error, error_description: error_description }.to_json)
    end

    def get_client(client_id)
      request(:get, "/admin/clients/#{client_id}")
    end

    private

    def request(method, path, options = {})
      response = self.class.send(method, path, options.merge(headers: json_headers))

      unless response.success?
        raise Spirely::HydraError.new(
          "Hydra admin API #{method.upcase} #{path} returned #{response.code}",
          status: response.code,
          body:   response.body
        )
      end

      response.parsed_response
    end

    def json_headers
      { "Content-Type" => "application/json", "Accept" => "application/json" }
    end
  end
end
