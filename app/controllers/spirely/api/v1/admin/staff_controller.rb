module Spirely
  module Api
    module V1
      module Admin
        # Read model for the Settings "Team" screen — current staff
        # Memberships plus any still-pending invites, in one call so the
        # UI doesn't need to stitch two fetches together itself.
        class StaffController < BaseController
          before_action :require_admin!

          # GET /api/v1/admin/staff
          def show
            members = Current.church.memberships.where(role: %w[admin owner])
                                     .includes(:account).order(:created_at)

            invitations = Current.church.staff_invitations.active.order(created_at: :desc)

            render json: {
              members: members.map { |m|
                { id: m.id, email: m.account.email, name: m.account.name, role: m.role, since: m.created_at }
              },
              pending_invitations: invitations.map { |i|
                { id: i.id, first_name: i.invited_first_name, email: i.invited_email,
                  phone: i.invited_phone, expires_at: i.expires_at, created_at: i.created_at }
              },
            }
          end
        end
      end
    end
  end
end
