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

          # PATCH /api/v1/admin/groups/:id — schedule settings (5ST-55):
          # head leader, which hosting jobs are on, and a repeat for groups
          # with no upcoming Planning Center events.
          def update
            group = Current.church.groups.active.find(params[:id])
            Spirely::Group.transaction do
              if params.key?(:head_leader_person_id)
                group.memberships.update_all(head_leader: false)
                if params[:head_leader_person_id].present?
                  leader = group.memberships.current.leaders.find_by!(person_id: params[:head_leader_person_id])
                  leader.update!(head_leader: true)
                end
              end
              group.schedule_jobs = Array(params[:schedule_jobs]).map(&:to_s).reject(&:blank?) if params.key?(:schedule_jobs)
              group.cadence_weekday = params[:cadence_weekday].presence&.to_i if params.key?(:cadence_weekday)
              group.cadence_interval_weeks = params[:cadence_interval_weeks].to_i if params[:cadence_interval_weeks].present?
              group.cadence_anchor_on ||= Spirely::ChurchTime.today(Current.church) if group.cadence_weekday
              group.save!
            end
            render json: group_detail_json(Spirely::GroupHealthCalculator.new(Current.church).health_for(group.reload))
          rescue ActiveRecord::RecordNotFound
            render json: { error: "Not found", code: "not_found" }, status: :not_found
          rescue ActiveRecord::RecordInvalid => e
            render json: { error: e.record.errors.full_messages.first, code: "validation_error" }, status: :unprocessable_entity
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
