module Spirely
  module Api
    module V1
      # The accept/decline page behind schedule emails and texts
      # (/schedule/r/:token, 5ST-55). No sign-in: the link token is the
      # credential. GET only reads — answering is always the POST from the
      # page's confirm button, so an email scanner opening the link can't
      # answer for anyone. A link stops working once the slot is given to
      # someone else (new token) or the meeting day ends.
      class ScheduleResponsesController < BaseController
        skip_before_action :authenticate!
        before_action :set_slot

        # GET /api/v1/schedule_responses/:token
        def show
          render json: response_json
        end

        # POST /api/v1/schedule_responses/:token  { choice: accept|decline }
        def create
          unless @slot.answerable?
            return render json: { error: "This link has expired.", code: "expired" }, status: :unprocessable_entity
          end
          Spirely::GroupSchedule.respond!(@slot, params.require(:choice))
          render json: response_json
        rescue Spirely::GroupSchedule::Error, ActionController::ParameterMissing => e
          render json: { error: e.message, code: "validation_error" }, status: :unprocessable_entity
        end

        private

        def set_slot
          @slot = Current.church.group_schedule_assignments.find_by_token(params[:token])
          return if @slot && @slot.person

          render json: { error: "This link isn't active anymore — the spot may have been given to someone else.",
                         code: "not_found" }, status: :not_found
        end

        def response_json
          zone = Spirely::ChurchTime.zone(Current.church)
          {
            church_name: Current.church.name,
            first_name:  @slot.person.first_name,
            group_name:  @slot.group.name,
            job:         @slot.job,
            job_label:   @slot.job_label,
            job_verb:    @slot.job_verb,
            meets_on:    @slot.meets_on,
            when:        [@slot.meets_on.strftime("%A, %b %-d"), @slot.group_event&.starts_at&.in_time_zone(zone)&.strftime("%-l:%M%P")].compact.join(" · "),
            where:       @slot.group.location_name,
            asked_by:    @slot.assigned_by_account&.name,
            status:      @slot.status,
            answerable:  @slot.answerable?,
          }
        end
      end
    end
  end
end
