module Spirely
  module Api
    module V1
      module Admin
        class StaffInvitationsController < BaseController
          before_action :require_admin!

          # POST /api/v1/admin/staff_invitations { first_name:, last_name:, email:, phone: }
          def create
            if params[:email].blank? && params[:phone].blank?
              render json: { error: "An email or phone number is required", code: "validation_error" },
                     status: :unprocessable_entity
              return
            end

            # Same expire-prior-pending pattern the family/guardian invite
            # flows use — avoids a stray earlier invite to the same person
            # staying active alongside a fresh one.
            if params[:email].present?
              Current.church.staff_invitations.active.where(invited_email: params[:email])
                     .update_all(expires_at: Time.current)
            end

            invitation = Current.church.staff_invitations.create!(
              invited_first_name: params[:first_name],
              invited_last_name:  params[:last_name],
              invited_email:      params[:email],
              invited_phone:      params[:phone]
            )

            invite_methods = Spirely::InviteSender.call(
              church:      Current.church,
              first_name:  params[:first_name],
              phone:       params[:phone],
              email:       params[:email],
              invitation:  invitation,
              mailer:      Spirely::StaffInviteMailer,
              sms_purpose: "You've been added as staff — accept your invite"
            )

            render json: { invite_url: invitation.invite_url, invite_methods: invite_methods }, status: :created
          rescue ActiveRecord::RecordInvalid => e
            render json: { error: e.message, code: "validation_error" }, status: :unprocessable_entity
          end
        end
      end
    end
  end
end
