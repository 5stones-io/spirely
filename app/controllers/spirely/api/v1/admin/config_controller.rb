module Spirely
  module Api
    module V1
      module Admin
        class ConfigController < BaseController
          before_action :require_admin!

          def show
            integration = Current.church.church_integration

            render json: {
              pco_auth_method: integration&.token_type || "oauth",
              pco_app_configured: integration&.pco_app_configured? || false,
              pco_pat_configured: integration&.pco_pat_configured? || false,
              pco_connected: pco_connected?(integration),
              pco_redirect_uri: pco_redirect_uri,
              twilio_configured: integration&.twilio_configured? || false,
              twilio_verified: integration&.twilio_verified? || false,
              public_site_theme: Current.church.public_site_theme,
            }
          end

          # Lets a church admin register their own church's PCO credentials
          # — either an OAuth app (client_id/secret, requires the separate
          # GET /auth/pco/connect consent step afterward) or a Personal
          # Access Token (app_id/secret, usable immediately — PATs
          # authenticate directly on every API call, no handshake). Both
          # can be saved at once; whichever was JUST saved becomes the
          # active token_type PcoClient actually uses (see
          # Spirely::ChurchIntegration#personal_token?) — saving one
          # doesn't erase the other, only switches which is live.
          def update
            integration = Current.church.church_integration || Current.church.build_church_integration(token_type: "oauth")

            attrs = config_params
            theme = attrs.delete(:public_site_theme)

            if attrs[:pco_pat_app_id].present? || attrs[:pco_pat_secret].present?
              attrs = attrs.merge(token_type: "personal")
            elsif attrs[:pco_client_id].present? || attrs[:pco_client_secret].present?
              attrs = attrs.merge(token_type: "oauth")
            end

            # public_site_theme lives on Church, not ChurchIntegration — a
            # separate save, but still one PATCH /admin/config endpoint
            # from the frontend's perspective, same as every other knob
            # this screen manages.
            if theme.present? && !Current.church.update(public_site_theme: theme)
              render json: { error: Current.church.errors.full_messages.first, code: "validation_error" },
                     status: :unprocessable_entity
              return
            end

            if integration.update(attrs)
              render json: {
                pco_auth_method: integration.token_type,
                pco_app_configured: integration.pco_app_configured?,
                pco_pat_configured: integration.pco_pat_configured?,
                pco_connected: pco_connected?(integration),
                pco_redirect_uri: pco_redirect_uri,
                twilio_configured: integration.twilio_configured?,
                twilio_verified: integration.twilio_verified?,
                public_site_theme: Current.church.public_site_theme,
              }
            else
              render json: { error: integration.errors.full_messages.first, code: "validation_error" },
                     status: :unprocessable_entity
            end
          end

          # Mints the URL the browser should navigate to for "Connect
          # Planning Center". /auth/pco/connect has to be a plain top-level
          # navigation (it 302s to PCO's consent screen), which can never
          # carry this app's Authorization header — so this mints a
          # short-lived signed token (church-scoped, 5 min) that travels as
          # a query param instead, which Auth::PcoController accepts in
          # place of the header for just this one redirect step. Same
          # mechanism whether the settings screen calling this happens to be
          # same-origin (it always is now) or not.
          def connect_url
            token = Rails.application.message_verifier(:pco_connect)
                          .generate({ "church_id" => Current.church.id }, expires_in: 5.minutes)
            render json: { url: "#{request.base_url}/auth/pco/connect?token=#{CGI.escape(token)}" }
          end

          private

          def pco_connected?(integration)
            return false unless integration&.pco_connected?
            integration.expires_at.nil? || integration.expires_at > Time.current
          end

          # Same fixed-platform-callback value/fallback as
          # Auth::PcoController#pco_callback_url — every church's PCO OAuth
          # app must register this exact redirect URI.
          def pco_redirect_uri
            Spirely.configuration.pco_redirect_uri.presence || "#{request.base_url}/auth/pco/callback"
          end

          def config_params
            params.require(:config).permit(
              :pco_client_id, :pco_client_secret,
              :pco_pat_app_id, :pco_pat_secret,
              :twilio_account_sid, :twilio_auth_token, :twilio_from_number,
              :public_site_theme
            )
          end
        end
      end
    end
  end
end
