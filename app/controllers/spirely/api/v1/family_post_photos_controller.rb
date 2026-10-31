module Spirely
  module Api
    module V1
      # Serves a family post's photo from the signed token in its link (see
      # FamilyPostPhotosJson), the way IncidentPhotosController does in
      # spirely-cloud. Not a BaseController: an image tag can't send the
      # sign-in header, so the token is the whole check.
      class FamilyPostPhotosController < ActionController::API
        # ActionController::API doesn't set this; the Disk service (dev,
        # test) needs it to build a URL.
        before_action { ActiveStorage::Current.url_options = { host: request.host, port: request.port, protocol: request.protocol } }

        # GET /api/v1/family_post_photos/:signed_id
        def show
          blob = ActiveStorage::Blob.find_signed(params[:signed_id], purpose: "family_post_photo")
          return render_not_found unless blob&.attachments&.any? { |a| a.record_type == "Spirely::FamilyPost" }

          redirect_to blob.url(expires_in: 5.minutes, disposition: "inline"), allow_other_host: true
        end

        private

        def render_not_found
          render json: { error: "Not found", code: "not_found" }, status: :not_found
        end
      end
    end
  end
end
