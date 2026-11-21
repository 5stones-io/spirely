module Spirely
  module Api
    module V1
      module Admin
        # New families waiting for approval (5ST-85). Approving creates the
        # family and sends the normal invite; declining just closes it.
        class FamilySignupsController < BaseController
          before_action { require_feature!("family_signup") }
          before_action :require_admin!
          before_action :set_signup, only: %i[approve decline]

          # GET /api/v1/admin/family_signups — the ones waiting, oldest first.
          def index
            signups = Current.church.family_signups.waiting.includes(:matched_family).order(:submitted_at, :id)
            render json: { family_signups: signups.map { |s| signup_json(s) } }
          end

          # POST /api/v1/admin/family_signups/:id/approve
          def approve
            @signup.approve!(by: Current.account)
            render json: { family_signup: signup_json(@signup.reload) }
          rescue Spirely::FamilySignup::NotPending
            not_pending
          end

          # POST /api/v1/admin/family_signups/:id/decline
          def decline
            @signup.decline!(by: Current.account)
            render json: { family_signup: signup_json(@signup.reload) }
          rescue Spirely::FamilySignup::NotPending
            not_pending
          end

          private

          def set_signup
            @signup = Current.church.family_signups.find(params[:id])
          end

          def not_pending
            render json: { error: "This sign-up was already approved or declined.", code: "not_pending" },
                   status: :unprocessable_entity
          end

          def signup_json(s)
            d = s.details
            {
              id: s.id, status: s.status, phone: s.phone, email: s.email,
              first_name: d["first_name"], last_name: d["last_name"], address: d["address"],
              children: Array(d["children"]),
              matched_family: s.matched_family && { id: s.matched_family.id, name: s.matched_family.family_name },
              family_id: s.family_id, submitted_at: s.submitted_at,
            }
          end
        end
      end
    end
  end
end
