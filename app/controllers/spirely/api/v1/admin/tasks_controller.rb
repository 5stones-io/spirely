module Spirely
  module Api
    module V1
      module Admin
        # v1 scope (5ST-6): the Spirely-native Task entity's own CRUD —
        # no PCO Workflow sync here yet (see Spirely::Task's own comment).
        class TasksController < BaseController
          include Spirely::TaskEndpoints

          before_action :require_admin!
          before_action :set_task, only: %i[show update destroy]

          # GET /api/v1/admin/tasks?status=in_progress&assignee_membership_id=1
          def index
            scope = Current.church.tasks.includes(:assignee, :created_by, :time_category)
            scope = scope.where(status: params[:status]) if params[:status].present?
            scope = scope.where(assignee_membership_id: params[:assignee_membership_id]) if params[:assignee_membership_id].present?

            tasks = scope.order(created_at: :desc).page(params[:page]).per(50)

            render json: {
              tasks: tasks.map { |t| task_json(t) },
              meta:  pagination_meta(tasks),
            }
          end

          # GET /api/v1/admin/tasks/:id
          def show
            render json: task_json(@task)
          end

          # POST /api/v1/admin/tasks
          def create
            task = Current.church.tasks.new(task_params)
            task.created_by = Current.membership
            if task.time_category_id.nil?
              return render json: { error: "Pick a category for this task.", code: "validation_error" }, status: :unprocessable_entity
            end

            task.save!

            render json: task_json(task), status: :created
          rescue ActiveRecord::RecordInvalid => e
            render json: { error: e.message, code: "validation_error" }, status: :unprocessable_entity
          end

          # PATCH /api/v1/admin/tasks/:id
          def update
            update_task!(@task, task_params)
            render json: task_json(@task)
          rescue ActiveRecord::RecordInvalid => e
            render json: { error: e.message, code: "validation_error" }, status: :unprocessable_entity
          end

          # DELETE /api/v1/admin/tasks/:id
          def destroy
            @task.destroy!
            head :no_content
          end

          private

          def set_task
            @task = Current.church.tasks.find(params[:id])
          end

          def task_params
            params.require(:task).permit(
              :title, :description, :status, :due_date, :assignee_membership_id,
              :recurrence_rule, :recurrence_interval, :recurrence_mode, :sync_to_pco, :time_category_id
            ).tap { |attrs| check_time_category!(attrs) }
          end

        end
      end
    end
  end
end
