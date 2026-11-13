module Spirely
  module Api
    module V1
      # Feedback and requests (5ST-80): anyone at the church (a family, or
      # an account with a membership here) sends feedback and sees their
      # own submissions' status. Staff work through it in
      # Admin::FeedbackController.
      class FeedbackController < BaseController
        include Spirely::FeedbackJson

        before_action :require_member!

        # GET /api/v1/feedback
        def index
          feedback = own_feedback.with_attached_attachments.order(created_at: :desc, id: :desc).limit(100)
          render json: { feedback: feedback.map { |f| feedback_json(f) } }
        end

        # POST /api/v1/feedback
        #
        # Attachments come as feedback[attachments][] in a multipart body.
        # They're checked before any is uploaded, and a bad one saves nothing.
        def create
          feedback = Current.church.feedbacks.new(feedback_params)
          feedback.account = Current.account
          feedback.family = current_family
          feedback.sender_role = sender_role
          Feedback.transaction do
            feedback.save!
            feedback.attach_files(attachment_params) if attachment_params.present?
          end
          Spirely::FeedbackNotifier.submitted(feedback)

          render json: feedback_json(feedback), status: :created
        rescue ActiveRecord::RecordInvalid, Feedback::AttachmentError => e
          render json: { error: e.message, code: "validation_error" }, status: :unprocessable_entity
        end

        # GET /api/v1/feedback/about_options
        #
        # What "Which event or room?" offers. The gem knows the church's
        # rooms; a host app with its own events adds them by overriding
        # #about_event_options.
        def about_options
          rooms = Current.church.locations.order(:name).distinct.pluck(:name)
          render json: { events: about_event_options, rooms: rooms }
        end

        private

        def about_event_options = []

        def own_feedback
          Current.church.feedbacks.where(account_id: Current.account.id)
        end

        def require_member!
          return if Current.membership || current_family
          render json: { error: "You're not part of this church", code: "forbidden" }, status: :forbidden
        end

        def sender_role
          return "staff" if Current.membership&.admin_or_owner? || Current.membership&.staff?
          return "parent" if current_family
          "member"
        end

        def feedback_params
          params.require(:feedback).permit(:category, :tone, :about, :body)
        end

        def attachment_params
          params.require(:feedback).permit(attachments: [])[:attachments]
        end
      end
    end
  end
end
