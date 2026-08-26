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
              display_name: Current.church.display_name,
              logo_url: logo_url,
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
            display_name_provided = attrs.key?(:display_name)
            theme = attrs.delete(:public_site_theme)
            display_name = attrs.delete(:display_name)
            logo = attrs.delete(:logo)

            if attrs[:pco_pat_app_id].present? || attrs[:pco_pat_secret].present?
              attrs = attrs.merge(token_type: "personal")
            elsif attrs[:pco_client_id].present? || attrs[:pco_client_secret].present?
              attrs = attrs.merge(token_type: "oauth")
            end

            # public_site_theme/display_name/logo all live on Church, not
            # ChurchIntegration — separate saves, but still one PATCH
            # /admin/config endpoint from the frontend's perspective, same
            # as every other knob this screen manages. display_name is
            # blank-clearable (an empty string sent on purpose falls back
            # to Church#name via #brand_name — captured as
            # display_name_provided BEFORE the delete above, since an
            # empty string is falsy-by-`.present?` but still a real,
            # deliberate "clear this" request, distinct from the field
            # not being sent at all); logo is only ever attached, never
            # sent blank — see #remove_logo for clearing it.
            church_attrs = {}
            church_attrs[:public_site_theme] = theme if theme.present?
            church_attrs[:display_name] = display_name if display_name_provided
            if church_attrs.any?
              unless Current.church.update(church_attrs)
                render json: { error: Current.church.errors.full_messages.first, code: "validation_error" },
                       status: :unprocessable_entity
                return
              end
            end
            if logo.present?
              Current.church.logo.attach(logo)
              unless Current.church.valid?
                Current.church.logo.purge
                render json: { error: Current.church.errors.full_messages.first, code: "validation_error" },
                       status: :unprocessable_entity
                return
              end
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
                display_name: Current.church.display_name,
                logo_url: logo_url,
              }
            else
              render json: { error: integration.errors.full_messages.first, code: "validation_error" },
                     status: :unprocessable_entity
            end
          end

          # DELETE /api/v1/admin/config/logo — separate from #update since
          # "remove the logo" isn't expressible as a PATCH body value the
          # same way clearing a text field is.
          def remove_logo
            Current.church.logo.purge if Current.church.logo.attached?
            render json: { logo_url: nil }
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

          # url_for's polymorphic dispatch relies on view-layer machinery
          # this controller (ActionController::API) doesn't have — the
          # documented, controller-safe way to build an Active Storage URL
          # is the explicit route helper instead.
          def logo_url
            return nil unless Current.church.logo.attached?
            Rails.application.routes.url_helpers.rails_blob_url(Current.church.logo, host: request.base_url)
          end

          def config_params
            params.require(:config).permit(
              :pco_client_id, :pco_client_secret,
              :pco_pat_app_id, :pco_pat_secret,
              :twilio_account_sid, :twilio_auth_token, :twilio_from_number,
              :public_site_theme, :display_name, :logo
            )
          end
        end
      end
    end
  end
end
