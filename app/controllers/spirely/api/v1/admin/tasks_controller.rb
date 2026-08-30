module Spirely
  module Api
    module V1
      module Admin
        # v1 scope (5ST-6): the Spirely-native Task entity's own CRUD —
        # no PCO Workflow sync here yet (see Spirely::Task's own comment).
        class TasksController < BaseController
          before_action :require_admin!
          before_action :set_task, only: %i[show update destroy]

          # GET /api/v1/admin/tasks?status=in_progress&assignee_membership_id=1
          def index
            scope = Current.church.tasks.includes(:assignee, :created_by)
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
            task.save!

            render json: task_json(task), status: :created
          rescue ActiveRecord::RecordInvalid => e
            render json: { error: e.message, code: "validation_error" }, status: :unprocessable_entity
          end

          # PATCH /api/v1/admin/tasks/:id
          def update
            @task.update!(task_params)
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
            params.require(:task).permit(:title, :description, :status, :due_date, :assignee_membership_id)
          end

          def task_json(task)
            {
              id:          task.id,
              title:       task.title,
              description: task.description,
              status:      task.status,
              due_date:    task.due_date,
              assignee:    task.assignee && { id: task.assignee.id, email: task.assignee.account.email },
              created_by:  task.created_by && { id: task.created_by.id, email: task.created_by.account.email },
              created_at:  task.created_at,
              updated_at:  task.updated_at,
            }
          end
        end
      end
    end
  end
end
