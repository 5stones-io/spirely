require "httparty"

module Spirely
  class PcoClient
    PCO_BASE_URL  = "https://api.planningcenteronline.com"
    PCO_TOKEN_URL = "https://api.planningcenteronline.com/oauth/token"
    PAGE_SIZE     = 100

    def initialize(integration = nil)
      @integration = integration || ChurchIntegration.current
      validate_integration!
    end

    # Single-page GET — returns parsed response hash
    def get(path, params = {})
      request(:get, path, query: params)
    end

    # Fetches every page; returns { "data" => [...], "included" => [...] }
    # Use this when sync jobs need JSON:API `included` side-loaded records.
    def paginate(path, params = {})
      result = { "data" => [], "included" => [] }
      query  = params.merge(per_page: PAGE_SIZE)
      path   = path  # mutable below

      loop do
        response = get(path, query)
        result["data"].concat(response["data"] || [])
        result["included"].concat(response["included"] || [])

        next_link = response.dig("links", "next").presence
        break unless next_link

        uri   = URI.parse(next_link)
        path  = uri.path
        query = URI.decode_www_form(uri.query.to_s).to_h
      end

      result
    end

    # Fetches every page and returns the full flat array of "data" objects
    def get_all(path, params = {})
      results  = []
      next_url = "#{PCO_BASE_URL}#{path}"
      query    = params.merge(per_page: PAGE_SIZE)

      while next_url
        response = raw_request(:get, next_url, query: query, full_url: true)
        body     = parse!(response)
        results.concat(Array(body["data"]))
        next_url = body.dig("links", "next").presence
        query    = {}  # subsequent pages use the full next_url, no extra params
      end

      results
    end

    def post(path, body = {})
      request(:post, path, body: body.to_json)
    end

    def patch(path, body = {})
      request(:patch, path, body: body.to_json)
    end

    def delete(path)
      request(:delete, path)
    end

    private

    # ------------------------------------------------------------------
    # Request plumbing
    # ------------------------------------------------------------------

    def request(method, path, options = {})
      response = raw_request(method, "#{PCO_BASE_URL}#{path}", options)

      if response.code == 401
        refresh_token!
        response = raw_request(method, "#{PCO_BASE_URL}#{path}", options)
      end

      parse!(response)
    end

    def raw_request(method, url, options = {}, full_url: false)
      target = full_url ? url : url  # already absolute in both branches

      log_request(method, target, options)

      response = HTTParty.send(
        method,
        target,
        options.merge(headers: json_headers)
      )

      log_response(response)
      response
    end

    def parse!(response)
      unless response.success?
        raise PcoApiError.new(
          "PCO API returned #{response.code}",
          status: response.code,
          body:   response.body
        )
      end
      response.parsed_response
    end

    # ------------------------------------------------------------------
    # Token refresh
    # ------------------------------------------------------------------

    def refresh_token!
      log "[Spirely::PcoClient] Refreshing access token"

      response = HTTParty.post(PCO_TOKEN_URL, body: {
        grant_type:    "refresh_token",
        refresh_token: @integration.refresh_token,
        client_id:     Spirely.configuration.pco_client_id,
        client_secret: Spirely.configuration.pco_client_secret
      })

      unless response.success?
        raise PcoAuthError, "Token refresh failed (#{response.code}): #{response.body}"
      end

      body = response.parsed_response
      @integration.update_tokens!(
        access:     body["access_token"],
        refresh:    body["refresh_token"],
        expires_in: body["expires_in"]
      )

      log "[Spirely::PcoClient] Token refreshed, expires #{@integration.expires_at}"
    end

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def json_headers
      {
        "Authorization" => "Bearer #{@integration.access_token}",
        "Content-Type"  => "application/json",
        "Accept"        => "application/json"
      }
    end

    def validate_integration!
      raise ConfigError, "No ChurchIntegration record — connect PCO first" unless @integration.persisted?
      raise ConfigError, "PCO access token is blank — connect PCO first" unless @integration.pco_connected?
    end

    def log(msg)
      Rails.logger.debug(msg) if debug?
    end

    def log_request(method, url, options)
      return unless debug?
      safe = options.except(:headers)  # don't log auth headers
      Rails.logger.debug("[Spirely::PcoClient] → #{method.upcase} #{url} #{safe.inspect}")
    end

    def log_response(response)
      return unless debug?
      preview = response.body&.slice(0, 500)
      Rails.logger.debug("[Spirely::PcoClient] ← #{response.code} #{preview}")
    end

    def debug?
      ENV["DEBUG_PCO_SYNC"] == "true"
    end
  end
end
