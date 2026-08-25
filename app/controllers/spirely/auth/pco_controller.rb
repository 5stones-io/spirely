module Spirely
  module Auth
    class PcoController < ApplicationController
      PCO_AUTH_URL  = "https://api.planningcenteronline.com/oauth/authorize"
      PCO_TOKEN_URL = "https://api.planningcenteronline.com/oauth/token"

      # Each church registers its own PCO OAuth app (client_id/secret stored
      # per-church on ChurchIntegration, not a shared platform app) — but all
      # churches register the SAME fixed redirect_uri
      # (Spirely.configuration.pco_redirect_uri), since that's a single
      # value every church's PCO app setup instructions can point at
      # unchanged. That's also why the callback still needs the `state`-param
      # church recovery below: the callback request itself always lands on
      # that one shared redirect_uri host, never a per-church subdomain, so
      # Current.church (Host-header-resolved) is meaningless there.
      before_action :require_tenant!,     only: [:connect]
      before_action :authorize_connect!, only: [:connect]

      def connect
        integration = Current.church.church_integration

        if integration&.personal_token?
          render plain: "This church is using a Personal Access Token — there's no OAuth consent " \
                        "step to complete. It's already connected once saved in Settings.",
                 status: :unprocessable_entity
          return
        end

        unless integration&.pco_client_id.present? && integration[:pco_client_secret].present?
          render plain: "PCO isn't configured for this church yet — add your PCO app's Client ID " \
                        "and Secret in Settings first.", status: :unprocessable_entity
          return
        end

        auth_params = {
          client_id:     integration.pco_client_id,
          redirect_uri:  pco_callback_url,
          response_type: "code",
          scope:         "people check_ins calendar services",
          state:         Current.church.id
        }
        redirect_to "#{PCO_AUTH_URL}?#{auth_params.to_query}", allow_other_host: true
      end

      def callback
        church = Church.find_by(id: params[:state])
        integration = church&.church_integration

        unless integration&.pco_app_configured?
          render plain: "PCO OAuth failed: no PCO app configured for this church.", status: :unprocessable_entity
          return
        end

        response = HTTParty.post(PCO_TOKEN_URL, body: {
          grant_type:    "authorization_code",
          code:          params[:code],
          client_id:     integration.pco_client_id,
          client_secret: integration.pco_client_secret,
          redirect_uri:  pco_callback_url
        })

        if response.success?
          body = response.parsed_response
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

      # This is a plain top-level browser navigation (it has to be — it ends
      # in a 302 to PCO's consent screen), which can never carry the JWT
      # Authorization header the rest of this app authenticates with. So it
      # accepts either: a real Rodauth-authenticated admin/owner session (in
      # case something ever does hit this with the header attached, e.g. a
      # test or a future non-browser caller), or a short-lived signed
      # `token` param minted by Manage::ChurchIntegrationsController#connect_url
      # for exactly this purpose. Same message_verifier + purpose string on
      # both ends.
      def authorize_connect!
        return if admin_session?
        return if valid_connect_token?
        render plain: "Forbidden", status: :forbidden
      end

      def admin_session?
        return false unless rodauth.authenticated?
        acct_id    = rodauth.session[rodauth.session_key]
        membership = Membership.find_by(account_id: acct_id, church_id: Current.church&.id)
        membership&.admin_or_owner? == true
      end

      def valid_connect_token?
        return false if params[:token].blank?
        data = Rails.application.message_verifier(:pco_connect).verify(params[:token])
        data["church_id"] == Current.church&.id
      rescue ActiveSupport::MessageVerifier::InvalidSignature
        false
      end

      def pco_callback_url
        Spirely.configuration.pco_redirect_uri.presence || "#{request.base_url}/auth/pco/callback"
      end
    end
  end
end
