module Spirely
  module Api
    module V1
      # Serves a feedback attachment from the signed token in its link (see
      # FeedbackJson), like FamilyPostPhotosController. Pictures open in
      # the browser; documents always download, so an Office or PDF file
      # never renders on our pages.
      class FeedbackAttachmentsController < ActionController::API
        # ActionController::API doesn't set this; the Disk service (dev,
        # test) needs it to build a URL.
        before_action { ActiveStorage::Current.url_options = { host: request.host, port: request.port, protocol: request.protocol } }

        # GET /api/v1/feedback_attachments/:signed_id
        def show
          blob = ActiveStorage::Blob.find_signed(params[:signed_id], purpose: "feedback_attachment")
          unless blob&.attachments&.any? { |a| a.record_type == "Spirely::Feedback" }
            return render json: { error: "Not found", code: "not_found" }, status: :not_found
          end

          disposition = Spirely::Feedback.picture?(blob.content_type) ? "inline" : "attachment"
          redirect_to blob.url(expires_in: 5.minutes, disposition: disposition), allow_other_host: true
        end
      end
    end
  end
end
