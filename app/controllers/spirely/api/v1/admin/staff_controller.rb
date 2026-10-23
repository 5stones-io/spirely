module Spirely
  module Api
    module V1
      module Admin
        # Read model for the Settings "Team" screen — current staff
        # Memberships plus any still-pending invites, in one call so the
        # UI doesn't need to stitch two fetches together itself. Also
        # members marked as staff (time card, without admin powers), and
        # marking or unmarking them.
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
              time_card_staff: Current.church.memberships.where(staff: true).where.not(role: %w[admin owner])
                                      .includes(:account).order(:created_at).map { |m|
                { id: m.id, email: m.account.email, name: m.account.name, role: m.role, since: m.created_at }
              },
              pending_invitations: invitations.map { |i|
                { id: i.id, first_name: i.invited_first_name, last_name: i.invited_last_name,
                  email: i.invited_email, phone: i.invited_phone, expires_at: i.expires_at,
                  created_at: i.created_at }
              },
            }
          end

          # GET /api/v1/admin/staff/candidates?q=
          # Church members (not admins) to mark as staff, by name or email.
          def candidates
            q = params[:q].to_s.strip
            return render json: { members: [] } if q.length < 2

            like = "%#{ActiveRecord::Base.sanitize_sql_like(q)}%"
            members = Current.church.memberships.where.not(role: %w[admin owner]).where(staff: false).joins(:account)
                             .where("accounts.email ILIKE :q OR COALESCE(accounts.first_name, '') || ' ' || COALESCE(accounts.last_name, '') ILIKE :q", q: like)
                             .includes(:account).limit(10)
            render json: { members: members.map { |m| { id: m.id, email: m.account.email, name: m.account.name } } }
          end

          # PATCH /api/v1/admin/staff/members/:id  { staff }
          def update_member
            member = Current.church.memberships.find(params[:id])
            member.update!(staff: ActiveModel::Type::Boolean.new.cast(params.require(:staff)))
            render json: { id: member.id, email: member.account.email, name: member.account.name, role: member.role, staff: member.staff }
          end
        end
      end
    end
  end
end
