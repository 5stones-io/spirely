module Spirely
  module Api
    module V1
      class StaffInvitationsController < ActionController::API
        include TenantResolution
        before_action :require_tenant!

        # GET /api/v1/staff_invitations/:token — public, no auth
        def show
          invitation = Current.church.staff_invitations.find_active(params[:token])

          if invitation.nil?
            render json: { error: "This invite link has expired or already been used.", code: "invalid_invite" },
                   status: :not_found
            return
          end

          render json: {
            token:      invitation.token,
            expires_at: invitation.expires_at,
            first_name: invitation.invited_first_name,
            email:      invitation.invited_email,
            phone:      invitation.invited_phone,
          }
        end

        # POST /api/v1/staff_invitations/:token/accept
        def accept
          unless rodauth.authenticated?
            render json: { error: "Unauthorized", code: "unauthorized" }, status: :unauthorized
            return
          end

          invitation = Current.church.staff_invitations.find_active(params[:token])
          if invitation.nil?
            render json: { error: "Invite link expired or already used.", code: "invalid_invite" },
                   status: :not_found
            return
          end

          invitation.accept!(rodauth.session[rodauth.session_key])
          render json: { status: "accepted" }
        end
      end
    end
  end
end
