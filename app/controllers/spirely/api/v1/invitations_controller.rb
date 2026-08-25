module Spirely
  module Api
    module V1
      class InvitationsController < ActionController::API
        include TenantResolution
        before_action :require_tenant!

        # GET /api/v1/invitations/:token  — public, no auth
        def show
          invitation = Current.church.invitations.merge(Invitation.active).find_by(token: params[:token])

          if invitation.nil?
            render json: { error: "This invite link has expired or already been used.", code: "invalid_invite" },
                   status: :not_found
            return
          end

          family   = invitation.family
          guardian = invitation.guardian

          render json: {
            token:      invitation.token,
            expires_at: invitation.expires_at,
            # Greets whoever this specific invite is actually for — the
            # family's own primary contact, or, for a guardian-scoped
            # invite (multi-account family access), that Guardian's own
            # name/email/phone, not always the primary contact's.
            family: {
              first_name: guardian&.first_name || family.primary_contact_first_name,
              last_name:  guardian&.last_name  || family.primary_contact_last_name,
              email:      guardian&.email      || family.email,
              phone:      guardian&.phone      || family.phone,
            }
          }
        end

        # POST /api/v1/invitations/:token/accept
        def accept
          unless rodauth.authenticated?
            render json: { error: "Unauthorized", code: "unauthorized" }, status: :unauthorized
            return
          end

          invitation = Current.church.invitations.merge(Invitation.active).find_by(token: params[:token])
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
