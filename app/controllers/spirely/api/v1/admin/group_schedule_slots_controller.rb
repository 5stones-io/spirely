module Spirely
  module Api
    module V1
      module Admin
        # Staff filling, clearing and re-sending schedule slots (5ST-55) —
        # the meeting sheet. All rules live in Spirely::GroupSchedule.
        class GroupScheduleSlotsController < BaseController
          include ScheduleJson

          before_action :require_admin!
          before_action -> { require_module!("smallgroups") }
          before_action :set_group

          # PUT /api/v1/admin/groups/:group_id/schedule_slot
          def update
            person = Current.church.people.find(params.require(:person_id))
            slot = schedule.assign!(meets_on: meets_on, job: params.require(:job), person: person,
                                    by_account: Current.account, source: "staff")
            render json: slot_json(slot)
          end

          # DELETE /api/v1/admin/groups/:group_id/schedule_slot?meets_on=&job=
          def destroy
            schedule.unassign!(meets_on: meets_on, job: params.require(:job))
            head :no_content
          end

          # POST /api/v1/admin/groups/:group_id/schedule_slot/resend
          def resend
            slot = @group.schedule_assignments.find_by!(meets_on: meets_on, job: params.require(:job))
            render json: slot_json(schedule.resend!(slot))
          end

          private

          def schedule = Spirely::GroupSchedule.new(@group)

          def meets_on = Date.parse(params.require(:meets_on))

          def set_group
            @group = Current.church.groups.active.find(params[:group_id])
          end

          rescue_from ActiveRecord::RecordNotFound do
            render json: { error: "Not found", code: "not_found" }, status: :not_found
          end
          rescue_from Spirely::GroupSchedule::Error, Date::Error, ActionController::ParameterMissing do |e|
            render json: { error: e.message, code: "validation_error" }, status: :unprocessable_entity
          end
        end
      end
    end
  end
end
