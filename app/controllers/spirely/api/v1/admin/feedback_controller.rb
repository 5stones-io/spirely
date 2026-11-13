module Spirely
  module Api
    module V1
      module Admin
        # Staff inbox for feedback and requests (5ST-80). Admins and owners
        # only. Making a task from feedback goes through
        # Admin::TasksController#create with task[feedback_id].
        class FeedbackController < BaseController
          include Spirely::FeedbackJson

          before_action :require_admin!
          before_action :set_feedback, only: %i[show update]

          # GET /api/v1/admin/feedback?status=new&category=supplies
          #
          # counts are by status, within the category picked.
          def index
            scope = Current.church.feedbacks
            scope = scope.where(category: params[:category]) if params[:category].present?
            counts = scope.group(:status).count
            scope = scope.where(status: params[:status]) if params[:status].present?

            feedback = scope.includes(:account, :family, :task).with_attached_attachments
                            .order(created_at: :desc, id: :desc).page(params[:page]).per(50)
            render json: {
              feedback: feedback.map { |f| staff_feedback_json(f) },
              counts:   { all: counts.values.sum }.merge(Spirely::Feedback::STATUSES.index_with { |s| counts.fetch(s, 0) }),
              meta:     pagination_meta(feedback),
            }
          end

          # GET /api/v1/admin/feedback/:id
          def show
            render json: staff_feedback_json(@feedback, attachments: true)
          end

          # PATCH /api/v1/admin/feedback/:id
          def update
            @feedback.update!(params.require(:feedback).permit(:status, :staff_note))
            render json: staff_feedback_json(@feedback, attachments: true)
          rescue ActiveRecord::RecordInvalid => e
            render json: { error: e.message, code: "validation_error" }, status: :unprocessable_entity
          end

          private

          def set_feedback
            @feedback = Current.church.feedbacks.find_by(id: params[:id])
            render json: { error: "Not found", code: "not_found" }, status: :not_found unless @feedback
          end
        end
      end
    end
  end
end
