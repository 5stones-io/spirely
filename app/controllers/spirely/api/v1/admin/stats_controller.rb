module Spirely
  module Api
    module V1
      module Admin
        class StatsController < BaseController
          before_action :require_admin!

          def show
            families = Current.church.families

            render json: {
              families: {
                total:   families.count,
                active:  families.where.not(account_id: nil).count,
                pending: families.where(account_id: nil).count,
              },
              children: Current.church.children.count,
              invitations: {
                pending: Current.church.invitations.where(accepted_at: nil)
                                        .where("expires_at > ?", Time.current).count,
              },
            }
          end
        end
      end
    end
  end
end
