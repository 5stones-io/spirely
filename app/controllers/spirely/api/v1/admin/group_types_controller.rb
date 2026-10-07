module Spirely
  module Api
    module V1
      module Admin
        # Settings → "Children's group types": the PCO group types synced by
        # PcoGroupsSyncJob, and which audience each one is. Every group of a
        # type inherits its audience (Spirely::Group#audience), which is
        # how Small Groups tells adult groups from children's groups.
        class GroupTypesController < BaseController
          before_action :require_admin!
          before_action :require_groups!

          # GET /api/v1/admin/group_types
          def index
            types = Current.church.group_types.current.order(:name)
            counts = Current.church.groups.active.group(:group_type_id).count
            render json: types.map { |t| as_json(t, counts[t.id] || 0) }
          end

          # PATCH /api/v1/admin/group_types/:id
          def update
            type = Current.church.group_types.find(params[:id])
            type.update!(audience: params.require(:audience))
            render json: as_json(type, Current.church.groups.active.where(group_type: type).count)
          rescue ActiveRecord::RecordNotFound
            render json: { error: "Not found", code: "not_found" }, status: :not_found
          rescue ActiveRecord::RecordInvalid => e
            render json: { error: e.record.errors.full_messages.first, code: "validation_error" },
                   status: :unprocessable_entity
          end

          private

          def as_json(type, groups_count)
            { id: type.id, name: type.name, color: type.color, audience: type.audience, groups_count: groups_count }
          end
        end
      end
    end
  end
end
