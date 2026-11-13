module Spirely
  module Api
    module V1
      module Admin
        # Read model for the Settings "Team" screen — current staff
        # Memberships plus any still-pending invites, in one call so the
        # UI doesn't need to stitch two fetches together itself. Also
        # members marked as staff (time card, without admin powers) or as
        # Kudos helpers (the store desk) or as pastors (who see "Pastors
        # only" prayer requests, 5ST-79), and marking or unmarking them.
        class StaffController < BaseController
          before_action :require_admin!

          FLAGS = %w[staff kudos_helper pastor].freeze

          # GET /api/v1/admin/staff
          def show
            members = Current.church.memberships.where(role: %w[admin owner])
                                     .includes(:account).order(:created_at)

            invitations = Current.church.staff_invitations.active.order(created_at: :desc)

            render json: {
              members: members.map { |m|
                { id: m.id, email: m.account.email, name: m.account.name, role: m.role, since: m.created_at }
              },
              time_card_staff: flagged(:staff),
              kudos_helpers: flagged(:kudos_helper),
              # Anyone can be a pastor, admins and owners included.
              pastors: flagged(:pastor, admins_too: true),
              pending_invitations: invitations.map { |i|
                { id: i.id, first_name: i.invited_first_name, last_name: i.invited_last_name,
                  email: i.invited_email, phone: i.invited_phone, expires_at: i.expires_at,
                  created_at: i.created_at }
              },
            }
          end

          # GET /api/v1/admin/staff/candidates?q=&flag=staff|kudos_helper|pastor
          # Church members to mark as staff, Kudos helpers or pastors, by
          # name or email. Only pastors can be admins too.
          def candidates
            q = params[:q].to_s.strip
            return render json: { members: [] } if q.length < 2

            like = "%#{ActiveRecord::Base.sanitize_sql_like(q)}%"
            members = Current.church.memberships.where(flag => false)
            members = members.where.not(role: %w[admin owner]) unless flag == "pastor"
            members = members.joins(:account)
                             .where("accounts.email ILIKE :q OR COALESCE(accounts.first_name, '') || ' ' || COALESCE(accounts.last_name, '') ILIKE :q", q: like)
                             .includes(:account).limit(10)
            render json: { members: members.map { |m| { id: m.id, email: m.account.email, name: m.account.name } } }
          end

          # PATCH /api/v1/admin/staff/members/:id  { staff, kudos_helper, pastor } (any of them)
          def update_member
            member = Current.church.memberships.find(params[:id])
            changes = params.permit(*FLAGS).to_h.transform_values { |v| ActiveModel::Type::Boolean.new.cast(v) }
            raise ActionController::ParameterMissing, FLAGS.join(" or ") if changes.empty?

            member.update!(changes)
            render json: { id: member.id, email: member.account.email, name: member.account.name, role: member.role,
                           staff: member.staff, kudos_helper: member.kudos_helper, pastor: member.pastor }
          end

          private

          def flag = FLAGS.include?(params[:flag]) ? params[:flag] : "staff"

          # Members with this flag on; not admins, unless admins_too.
          def flagged(column, admins_too: false)
            scope = Current.church.memberships.where(column => true)
            scope = scope.where.not(role: %w[admin owner]) unless admins_too
            scope.includes(:account).order(:created_at).map { |m|
              { id: m.id, email: m.account.email, name: m.account.name, role: m.role, since: m.created_at }
            }
          end
        end
      end
    end
  end
end
