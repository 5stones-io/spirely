module Spirely
  module Api
    module V1
      # My Groups (Small Groups, 5ST-55) — a leader's or member's own
      # schedule: requests waiting for their answer, their groups' upcoming
      # meetings, signing up for open spots, and (for a group's head
      # leader) scheduling that group. Roster, attendance and chat stay in
      # Church Center; this only covers what Spirely adds.
      class MyGroupsController < BaseController
        include ScheduleJson
        include FollowUpJson

        before_action -> { require_module!("smallgroups") }
        before_action :require_person!
        before_action :set_group, only: [:sign_up, :assign, :unassign]

        # GET /api/v1/my_groups
        def show
          memberships = current_group_memberships.sort_by { |m| [m.role == "leader" ? 0 : 1, m.group.name.downcase] }
          today = Spirely::ChurchTime.today(Current.church)
          requests = current_person.group_schedule_assignments.where(status: "pending").where("meets_on >= ?", today)
                                   .includes(:group, :group_event, :assigned_by_account).order(:meets_on)
          render json: {
            name: current_person.full_name,
            requests: requests.map { |s| request_json(s) },
            groups: memberships.map { |m| group_json(m) },
            # Open follow-ups for groups this person leads (5ST-53).
            follow_ups: led_follow_ups.map { |n| follow_up_json(n) },
          }
        end

        # GET /api/v1/my_groups/follow_ups/:id — leaders of that group only.
        def follow_up
          render json: follow_up_json(led_follow_up, detail: true)
        end

        # POST /api/v1/my_groups/follow_ups/:id/notes  { body, outcome? }
        def follow_up_notes
          log_follow_up(led_follow_up)
        end

        # POST /api/v1/my_groups/groups/:group_id/sign_up
        def sign_up
          slot = schedule.sign_up!(meets_on: meets_on, job: params.require(:job), person: current_person)
          render json: slot_json(slot)
        end

        # POST /api/v1/my_groups/slots/:id/respond — answering a request
        # while signed in (same rules as the emailed link).
        def respond
          slot = current_person.group_schedule_assignments.find(params[:id])
          return render(json: { error: "This date has passed.", code: "expired" }, status: :unprocessable_entity) if slot.meets_on < Spirely::ChurchTime.today(Current.church)

          render json: slot_json(Spirely::GroupSchedule.respond!(slot, params.require(:choice)))
        end

        # PUT /api/v1/my_groups/groups/:group_id/schedule_slot — head leader only.
        def assign
          return forbidden unless head_leader?
          person = Current.church.people.find(params.require(:person_id))
          slot = schedule.assign!(meets_on: meets_on, job: params.require(:job), person: person,
                                  by_account: Current.account, source: "head_leader")
          render json: slot_json(slot)
        end

        # DELETE /api/v1/my_groups/groups/:group_id/schedule_slot — head leader only.
        def unassign
          return forbidden unless head_leader?
          schedule.unassign!(meets_on: meets_on, job: params.require(:job))
          head :no_content
        end

        private

        def led_follow_ups
          led = current_group_memberships.select { |m| m.role == "leader" }.map(&:group_id)
          Current.church.group_nudges.open.where(group_id: led).includes(:group, :person, :owner_person).order(:created_at)
        end

        def led_follow_up = led_follow_ups.find(params[:id])

        def require_person!
          return if current_person
          render json: { error: "We couldn't match you to Planning Center — ask your church staff.", code: "person_not_found" },
                 status: :not_found
        end

        def set_group
          @membership = current_group_memberships.find { |m| m.group_id.to_s == params[:group_id].to_s }
          return render(json: { error: "Not found", code: "not_found" }, status: :not_found) unless @membership
          @group = @membership.group
        end

        def head_leader? = @group.head_leader == current_person
        def forbidden = render(json: { error: "Only this group's head leader can do that.", code: "forbidden" }, status: :forbidden)
        def schedule = Spirely::GroupSchedule.new(@group)
        def meets_on = Date.parse(params.require(:meets_on))

        def group_json(membership)
          group = membership.group
          head  = group.head_leader == current_person
          meetings = Spirely::GroupSchedule.new(group).meetings
          {
            id: group.id, name: group.name, schedule_text: group.schedule_text, location_name: group.location_name,
            role: membership.role, head_leader: head, church_center_url: group.church_center_url,
            jobs: group.jobs,
            people: (eligible_json(group) if head),
            meetings: meetings.map { |m|
              meeting_json(group, m).tap do |j|
                j[:slots].each do |s|
                  s[:mine] = s[:person]&.dig(:id) == current_person.id
                  # Open or turned down — anyone eligible can take it,
                  # including someone who declined and then found they can.
                  s[:can_sign_up] = %w[open declined].include?(s[:status]) &&
                                    (s[:job] != "lead" || membership.role == "leader")
                end
              end
            },
          }
        end

        def request_json(slot)
          zone = Spirely::ChurchTime.zone(Current.church)
          {
            id: slot.id, job: slot.job, job_label: slot.job_label, job_verb: slot.job_verb,
            group: { id: slot.group_id, name: slot.group.name, location_name: slot.group.location_name },
            meets_on: slot.meets_on, label: slot.meets_on.strftime("%a %b %-d"),
            time: slot.group_event&.starts_at&.in_time_zone(zone)&.strftime("%-l:%M%P"),
            asked_by: slot.assigned_by_account&.name,
          }
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
