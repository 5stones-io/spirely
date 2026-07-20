module Spirely
  module Api
    module V1
      class BaseController < ActionController::API
        before_action :authenticate!

        private

        def authenticate!
          unless rodauth.authenticated?
            render json: { error: "Unauthorized", code: "unauthorized" }, status: :unauthorized
            return
          end
          # In Rodauth JWT mode, @account is not loaded for incoming API requests —
          # only the JWT session payload is decoded. Read account_id from the session.
          acct_id = rodauth.session[rodauth.session_key]
          @current_family = Family.find_by(account_id: acct_id)
        end

        def current_family = @current_family

        # Read admin flag from the JWT payload (embedded in jwt_session_hash).
        def admin? = rodauth.session[:admin] == true

        def require_family!
          return if current_family
          render json: { error: "Family profile not found", code: "family_not_found" },
                 status: :not_found
        end

        def require_admin!
          return if admin?
          render json: { error: "Forbidden", code: "forbidden" }, status: :forbidden
        end

        def pagination_meta(collection)
          {
            total_count:  collection.total_count,
            current_page: collection.current_page,
            total_pages:  collection.total_pages,
            per_page:     collection.limit_value
          }
        end
      end
    end
  end
end
