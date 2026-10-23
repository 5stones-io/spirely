module Spirely
  module Api
    module V1
      # A staff member's own time card: hours for work outside normal
      # volunteer hours, each counted toward a category code. Admins, owners
      # and members marked as staff can use it; the person is always the
      # signed-in member.
      class TimeCardController < BaseController
        include Spirely::TimeCardJson

        before_action :require_time_card!

        TASK_RECENCY = 30.days

        # GET /api/v1/time_card?week_of=YYYY-MM-DD
        # The Monday-to-Sunday week containing week_of (this week by default).
        def show
          start = week_start
          entries = my_entries.where(worked_on: start..(start + 6)).includes(:time_category, :task).newest_first.to_a
          render json: {
            name: person_name(Current.membership), week_of: start, week_end: start + 6,
            entries: entries.map { |e| time_entry_json(e) },
            total_hours: entries.sum(&:hours).to_f,
            totals: totals_by_category(entries),
            categories: Current.church.time_categories.active.ordered.map { |c| time_category_json(c) },
            tasks: my_tasks.map { |t| { id: t.id, title: t.title, status: t.status, category: t.time_category && time_category_json(t.time_category) } },
          }
        end

        # POST /api/v1/time_entries  { task_id?, time_category_id?, title, description?, hours, worked_on }
        def create
          entry = my_entries.new(church: Current.church)
          save_entry(entry, :created)
        end

        # PATCH /api/v1/time_entries/:id
        def update
          save_entry(my_entries.find(params[:id]), :ok)
        end

        # DELETE /api/v1/time_entries/:id
        def destroy
          my_entries.find(params[:id]).destroy!
          head :no_content
        end

        private

        def require_time_card!
          return if Current.membership&.time_card?

          render json: { error: "The time card is for church staff.", code: "forbidden" }, status: :forbidden
        end

        def my_entries = Current.membership.time_entries

        # Tasks assigned to them that are open or were finished lately.
        def my_tasks
          Current.church.tasks.where(assignee_membership_id: Current.membership.id)
                 .where("status <> 'complete' OR completed_at >= ?", TASK_RECENCY.ago)
                 .includes(:time_category).order(:due_date, :title).limit(100)
        end

        def week_start
          day = params[:week_of].present? ? Date.iso8601(params[:week_of]) : Spirely::ChurchTime.today(Current.church)
          day.beginning_of_week(:monday)
        rescue Date::Error
          Spirely::ChurchTime.today(Current.church).beginning_of_week(:monday)
        end

        def save_entry(entry, status)
          attrs = params.permit(:title, :description, :hours, :worked_on).to_h
          entry.assign_attributes(attrs)
          if params.key?(:task_id)
            entry.task = params[:task_id].present? ? Current.church.tasks.find(params[:task_id]) : nil
          end
          if params.key?(:time_category_id)
            entry.time_category = params[:time_category_id].present? ? Current.church.time_categories.active.find(params[:time_category_id]) : nil
          end
          entry.save!
          render json: time_entry_json(entry), status: status
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.record.errors.full_messages.to_sentence, code: "validation_error" }, status: :unprocessable_entity
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Not found", code: "not_found" }, status: :not_found
        end
      end
    end
  end
end
