require "httparty"
require "base64"

module Spirely
  # Unlike self-hosted spirely (one PCO connection per deployment, defaulted
  # via ChurchIntegration.current), spirely-cloud has many churches sharing
  # one deployment — there is no sensible default integration, so the caller
  # must always pass the specific church's integration explicitly.
  class PcoClient
    PCO_BASE_URL  = "https://api.planningcenteronline.com"
    PCO_TOKEN_URL = "https://api.planningcenteronline.com/oauth/token"
    PAGE_SIZE     = 100

    def initialize(integration)
      @integration = integration
      validate_integration!
    end

    def get(path, params = {})
      request(:get, path, query: params)
    end

    def paginate(path, params = {})
      result = { "data" => [], "included" => [] }
      query  = params.merge(per_page: PAGE_SIZE)

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

    def get_all(path, params = {})
      results  = []
      next_url = "#{PCO_BASE_URL}#{path}"
      query    = params.merge(per_page: PAGE_SIZE)

      while next_url
        # { query: query } as an explicit hash literal, not a bare
        # `query: query` trailing arg — raw_request's explicit `full_url:`
        # keyword parameter forces strict keyword-argument matching on any
        # other `key: value` pairs passed alongside it at the call site,
        # so a bare `query: query` here raises "unknown keyword: :query"
        # instead of folding into the `options` positional param the way
        # it does on every other call site in this file (none of which
        # pass `full_url:` too). Pre-existing bug, never caught because no
        # test exercised get_all's multi-page path directly.
        response = raw_request(:get, next_url, { query: query }, full_url: true)
        body     = parse!(response)
        results.concat(Array(body["data"]))
        next_url = body.dig("links", "next").presence
        query    = {}
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

    def request(method, path, options = {})
      response = raw_request(method, "#{PCO_BASE_URL}#{path}", options)

      # A PAT has no refresh token to refresh — it authenticates directly on
      # every call, so a 401 there means the saved credentials are wrong/
      # revoked, not expired. Only OAuth's access_token is worth retrying.
      if response.code == 401 && !@integration.personal_token?
        refresh_token!
        response = raw_request(method, "#{PCO_BASE_URL}#{path}", options)
      end

      parse!(response)
    end

    def raw_request(method, url, options = {}, full_url: false)
      target = full_url ? url : url

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

    def refresh_token!
      log "[Spirely::PcoClient] Refreshing access token for church=#{@integration.church_id}"

      response = HTTParty.post(PCO_TOKEN_URL, body: {
        grant_type:    "refresh_token",
        refresh_token: @integration.refresh_token,
        client_id:     @integration.pco_client_id,
        client_secret: @integration.pco_client_secret
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

    def json_headers
      {
        "Authorization" => authorization_header,
        "Content-Type"  => "application/json",
        "Accept"        => "application/json"
      }
    end

    # PCO's own documented auth for a Personal Access Token: HTTP Basic,
    # username = App ID, password = Secret — not a bearer token, and
    # nothing to exchange/refresh (see #request's 401 handling above).
    def authorization_header
      if @integration.personal_token?
        credentials = Base64.strict_encode64("#{@integration.pco_pat_app_id}:#{@integration.pco_pat_secret}")
        "Basic #{credentials}"
      else
        "Bearer #{@integration.access_token}"
      end
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
      safe = options.except(:headers)
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
