module Spirely
  module Api
    module V1
      module Admin
        class ConfigController < BaseController
          before_action :require_admin!

          def show
            integration = ChurchIntegration.current

            render json: {
              twilio_enabled: SmsClient.configured?,
              pco_connected:  integration.access_token.present? &&
                              (integration.expires_at.nil? || integration.expires_at > Time.current),
            }
          end
        end
      end
    end
  end
end
