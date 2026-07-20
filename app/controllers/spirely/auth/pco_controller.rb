module Spirely
  module Auth
    class PcoController < ActionController::Base

      PCO_AUTH_URL  = "https://api.planningcenteronline.com/oauth/authorize"
      PCO_TOKEN_URL = "https://api.planningcenteronline.com/oauth/token"

      before_action :require_admin!

      def connect
        unless Spirely.configuration.pco_client_id.present?
          render plain: "PCO Client ID not configured. Save your PCO credentials first.", status: :unprocessable_entity
          return
        end

        auth_params = {
          client_id:     Spirely.configuration.pco_client_id,
          redirect_uri:  pco_callback_url,
          response_type: "code",
          scope:         "people check_ins calendar",
          state:         bearer_token
        }
        redirect_to "#{PCO_AUTH_URL}?#{auth_params.to_query}", allow_other_host: true
      end

      def callback
        response = HTTParty.post(PCO_TOKEN_URL, body: {
          grant_type:    "authorization_code",
          code:          params[:code],
          client_id:     Spirely.configuration.pco_client_id,
          client_secret: Spirely.configuration.pco_client_secret,
          redirect_uri:  pco_callback_url
        })

        if response.success?
          body        = response.parsed_response
          integration = Spirely::ChurchIntegration.current
          integration.token_type = "oauth"
          integration.update_tokens!(
            access:     body["access_token"],
            refresh:    body["refresh_token"],
            expires_in: body["expires_in"]
          )
          render plain: "PCO connected. You can close this tab."
        else
          render plain: "PCO OAuth failed: #{response.body}", status: :unprocessable_entity
        end
      end

      private

      def require_admin!
        unless rodauth.authenticated? && rodauth.rails_account&.admin?
          render plain: "Forbidden", status: :forbidden
        end
      end

      def bearer_token
        params[:token] || params[:state] || request.headers["Authorization"]&.split(" ")&.last
      end

      def pco_callback_url
        Spirely.configuration.pco_redirect_uri.presence || "#{request.base_url}/auth/pco/callback"
      end
    end
  end
end
