module Spirely
  # Feedback as the sender's list and the staff inbox show it (5ST-80).
  # Only the staff view carries attachment links and the staff note; each
  # link holds a 15-minute signed token that FeedbackAttachmentsController
  # serves.
  module FeedbackJson
    extend ActiveSupport::Concern

    private

    def feedback_json(feedback)
      {
        id:               feedback.id,
        category:         feedback.category,
        tone:             feedback.tone,
        about:            feedback.about,
        body:             feedback.body,
        status:           feedback.status,
        attachment_count: feedback.attachments_attachments.size,
        created_at:       feedback.created_at,
      }
    end

    def staff_feedback_json(feedback, attachments: false)
      feedback_json(feedback).merge(
        sender: {
          name:        feedback.sender_name,
          email:       feedback.account&.email,
          role:        feedback.sender_role,
          family_name: feedback.family&.family_name,
        },
        staff_note: feedback.staff_note,
        task: feedback.task && { id: feedback.task.id, title: feedback.task.title, status: feedback.task.status },
        updated_at: feedback.updated_at,
      ).tap do |json|
        json[:attachments] = feedback_attachments_json(feedback) if attachments
      end
    end

    def feedback_attachments_json(feedback)
      feedback.ordered_attachments.map do |attachment|
        blob  = attachment.blob
        token = blob.signed_id(expires_in: 15.minutes, purpose: "feedback_attachment")
        {
          id:           attachment.id,
          filename:     blob.filename.to_s,
          content_type: blob.content_type,
          byte_size:    blob.byte_size,
          kind:         Spirely::Feedback.picture?(blob.content_type) ? "picture" : "document",
          url:          "#{request.base_url}/api/v1/feedback_attachments/#{token}",
        }
      end
    end
  end
end
