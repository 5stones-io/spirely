module Spirely
  module Api
    module V1
      module Admin
        # Small Groups → Groups tab and group sheet (5ST-52). Read-only views
        # over the synced Planning Center Groups data plus
        # GroupHealthCalculator's flags. Filtering (audience, type, search)
        # happens client-side — a church's group count is small.
        class GroupsController < BaseController
          include GroupsJson

          before_action :require_admin!
          before_action -> { require_module!("smallgroups") }

          # GET /api/v1/admin/groups
          def index
            healths = Spirely::GroupHealthCalculator.new(Current.church).call
            render json: {
              groups: healths.map { |h| group_summary_json(h) },
              group_types: Current.church.group_types.current.order(:name).map { |t| { id: t.id, name: t.name, audience: t.audience } },
            }
          end

          # GET /api/v1/admin/groups/:id
          def show
            group = Current.church.groups.active.find(params[:id])
            health = Spirely::GroupHealthCalculator.new(Current.church).health_for(group)
            render json: group_detail_json(health)
          rescue ActiveRecord::RecordNotFound
            render json: { error: "Group not found", code: "not_found" }, status: :not_found
          end
        end
      end
    end
  end
end
