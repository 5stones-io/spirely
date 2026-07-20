module Spirely
  module Api
    module V1
      module Admin
        class StatsController < BaseController
          before_action :require_admin!

          def show
            render json: {
              families: {
                total:   Family.count,
                active:  Family.where.not(account_id: nil).count,
                pending: Family.where(account_id: nil).count,
              },
              children: Child.count,
              invitations: {
                pending: Invitation.where(accepted_at: nil)
                                   .where("expires_at > ?", Time.current).count,
              },
            }
          end
        end
      end
    end
  end
end
