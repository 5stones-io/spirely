module Spirely
  module Api
    module V1
      module Admin
        # Small Groups → Follow-ups tab (5ST-53): open and resolved
        # attendance follow-ups, with owner and history.
        class GroupNudgesController < BaseController
          include FollowUpJson

          RESOLVED_LIMIT = 50

          before_action :require_admin!
          before_action -> { require_module!("smallgroups") }
          before_action :set_nudge, except: :index

          # GET /api/v1/admin/group_nudges?status=open|resolved
          def index
            scope = Current.church.group_nudges.includes(:group, :person, :owner_person)
            nudges = params[:status] == "resolved" ? scope.resolved.order(resolved_at: :desc).limit(RESOLVED_LIMIT) : scope.open.order(:created_at)
            render json: { follow_ups: nudges.map { |n| follow_up_json(n) }, open_count: Current.church.group_nudges.open.count }
          end

          # GET /api/v1/admin/group_nudges/:id
          def show
            render json: follow_up_json(@nudge, detail: true)
          end

          # PATCH /api/v1/admin/group_nudges/:id  { owner_person_id }
          def update
            owner = params[:owner_person_id].presence && @nudge.group.current_leaders.find { |p| p.id == params[:owner_person_id].to_i }
            if params[:owner_person_id].present? && owner.nil?
              return render json: { error: "The owner has to be one of the group's leaders.", code: "validation_error" }, status: :unprocessable_entity
            end
            @nudge.update!(owner_person: owner)
            render json: follow_up_json(@nudge, detail: true)
          end

          # POST /api/v1/admin/group_nudges/:id/notes  { body, outcome? }
          def notes
            log_follow_up(@nudge)
          end

          private

          def set_nudge
            @nudge = Current.church.group_nudges.find(params[:id])
          rescue ActiveRecord::RecordNotFound
            render json: { error: "Not found", code: "not_found" }, status: :not_found
          end
        end
      end
    end
  end
end
