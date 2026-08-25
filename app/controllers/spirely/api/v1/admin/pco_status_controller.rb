module Spirely
  module Api
    module V1
      module Admin
        class PcoStatusController < BaseController
          before_action :require_admin!

          def show
            integration = Current.church.church_integration
            connected   = integration&.pco_connected? &&
                          (integration.expires_at.nil? || integration.expires_at > Time.current)

            render json: {
              connected:  connected || false,
              expires_at: integration&.expires_at,
            }
          end
        end
      end
    end
  end
end
