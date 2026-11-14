module Spirely
  module Api
    module V1
      # Staff see and edit the tasks assigned to them. They can't reassign a
      # task, change how it repeats, or create or delete one; admins do that
      # through Admin::TasksController.
      class MyTasksController < BaseController
        include Spirely::TaskEndpoints

        before_action :require_staff!
        before_action :set_task, only: %i[show update]

        # GET /api/v1/my_tasks?status=in_progress
        def index
          scope = my_tasks.includes({ assignee: :account }, { created_by: :account }, :time_category)
          scope = scope.where(status: params[:status]) if params[:status].present?
          tasks = scope.order(created_at: :desc).page(params[:page]).per(50)

          render json: { tasks: tasks.map { |t| task_json(t) }, meta: pagination_meta(tasks) }
        end

        # GET /api/v1/my_tasks/:id
        def show
          render json: task_json(@task)
        end

        # PATCH /api/v1/my_tasks/:id
        def update
          update_task!(@task, task_params)
          render json: task_json(@task)
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.message, code: "validation_error" }, status: :unprocessable_entity
        end

        private

        # Admins, owners and members marked as staff (same people as the
        # time card).
        def require_staff!
          return if Current.membership&.time_card?

          render json: { error: "Tasks are for church staff.", code: "forbidden" }, status: :forbidden
        end

        def my_tasks = Current.church.tasks.where(assignee_membership_id: Current.membership.id)

        def set_task
          @task = my_tasks.find(params[:id])
        end

        def task_params
          params.require(:task).permit(:title, :description, :status, :due_date, :time_category_id)
                .tap { |attrs| check_time_category!(attrs) }
        end
      end
    end
  end
end
