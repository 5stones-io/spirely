module Spirely
  module Api
    module V1
      module Admin
        # Multi-account family access: invites a specific Guardian to
        # claim their own login, independent of the family's own
        # primary-contact invite (Admin::FamiliesController#invite) —
        # both an existing "Adam Nelson" account and a newly-signed-up
        # "Becca Nelson" account can reach the same family afterward, see
        # Spirely::Invitation#accept!.
        class GuardianInvitationsController < BaseController
          before_action :require_admin!

          # POST /api/v1/admin/families/:family_id/guardians/:id/invite
          def invite
            family   = Current.church.families.find(params[:family_id])
            guardian = family.guardians.find(params[:id])

            guardian.invitations.where(accepted_at: nil).update_all(expires_at: Time.current)
            invitation = guardian.invitations.create!(family: family, church: Current.church)

            invite_methods = Spirely::InviteSender.call(
              church:     Current.church,
              first_name: guardian.first_name,
              phone:      guardian.phone,
              email:      guardian.email,
              invitation: invitation
            )

            render json: { invite_url: invitation.invite_url, invite_methods: invite_methods }
          end
        end
      end
    end
  end
end
