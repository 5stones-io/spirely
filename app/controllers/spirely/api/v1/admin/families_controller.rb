module Spirely
  module Api
    module V1
      module Admin
        class FamiliesController < BaseController
          before_action :require_admin!

          # GET /api/v1/admin/families
          def index
            families = Family.includes(:children, :account)
                             .order(created_at: :desc)
                             .page(params[:page]).per(50)

            render json: {
              families: families.map { |f|
                {
                  id:                         f.id,
                  family_name:                f.family_name,
                  primary_contact_first_name: f.primary_contact_first_name,
                  primary_contact_last_name:  f.primary_contact_last_name,
                  email:                      f.email,
                  phone:                      f.phone,
                  address:                    f.address,
                  children_count:             f.children.size,
                  account_linked:             f.account_id.present?,
                  pco_synced:                 f.pco_last_synced_at.present?,
                  created_at:                 f.created_at,
                }
              },
              meta: {
                total_count:  families.total_count,
                current_page: families.current_page,
                total_pages:  families.total_pages,
              },
            }
          end

          # GET /api/v1/admin/families/:id
          def show
            family = Family.includes(:children, :guardians, :account).find(params[:id])
            pending_invite = Invitation.where(family: family, accepted_at: nil)
                                       .where("expires_at > ?", Time.current)
                                       .order(created_at: :desc).first

            render json: {
              id:                         family.id,
              family_name:                family.family_name,
              primary_contact_first_name: family.primary_contact_first_name,
              primary_contact_last_name:  family.primary_contact_last_name,
              email:                      family.email,
              phone:                      family.phone,
              address:                    family.address,
              account_linked:             family.account_id.present?,
              pco_person_id:              family.pco_person_id,
              pco_household_id:           family.pco_household_id,
              pco_last_synced_at:         family.pco_last_synced_at,
              created_at:                 family.created_at,
              children:   family.children.map { |c|
                { id: c.id, first_name: c.first_name, last_name: c.last_name,
                  grade_display: c.grade_display, age: c.age, notes: c.notes }
              },
              guardians:  family.guardians.map { |g|
                { id: g.id, first_name: g.first_name, last_name: g.last_name,
                  phone: g.phone, email: g.email, relationship: g.relationship }
              },
              invite_url: pending_invite&.invite_url,
            }
          end

          # POST /api/v1/admin/families/:id/invite
          # Creates a fresh invitation (or returns the existing active one) and
          # optionally re-sends via SMS.
          def invite
            family = Family.find(params[:id])

            # Expire any old invitations so we start clean
            Invitation.where(family: family, accepted_at: nil).update_all(expires_at: Time.current)

            invitation    = Invitation.create!(family: family)
            invite_method = send_invite(family, invitation)

            render json: { invite_url: invitation.invite_url, invite_method: invite_method }
          end

          # POST /api/v1/admin/families
          # Quick-creates a family + children + invitation, optionally sends SMS.
          def create
            if family_params[:address].blank?
              return render json: { error: "Home address is required", code: "validation_error" },
                            status: :unprocessable_entity
            end

            family = build_family
            family.save!

            build_children(family)
            build_guardians(family)

            invitation    = Invitation.create!(family: family)
            invite_method = send_invite(family, invitation)

            # Push to PCO in the background only if already connected
            pco_connected   = ChurchIntegration.current.access_token.present? &&
                              (ChurchIntegration.current.expires_at.nil? ||
                               ChurchIntegration.current.expires_at > Time.current)
            pco_sync_queued = pco_connected
            PcoCreatePersonJob.perform_later(family.id) if pco_sync_queued

            render json: {
              family:          FamilyBlueprint.render_as_hash(family, view: :with_children),
              invite_url:      invitation.invite_url,
              invite_method:   invite_method,   # "sms" | "email" | "none"
              sms_sent:        invite_method == "sms",
              pco_sync_queued: pco_sync_queued,
            }, status: :created

          rescue ActiveRecord::RecordInvalid => e
            render json: { error: e.message, code: "validation_error" },
                   status: :unprocessable_entity
          end

          private

          def build_family
            p = family_params

            family_name = "#{p[:primary_contact_last_name]} Family"

            Family.new(
              family_name:                family_name,
              primary_contact_first_name: p[:primary_contact_first_name].presence,
              primary_contact_last_name:  p[:primary_contact_last_name].presence,
              phone:                      p[:phone],
              email:                      p[:email],
              address:                    p[:address]
            )
          end

          def build_children(family)
            return unless params[:children].present?

            params[:children].each do |child_params|
              next if child_params[:first_name].blank?

              family.children.create!(
                first_name: child_params[:first_name],
                last_name:  child_params[:last_name].presence || family.primary_contact_last_name,
                birthdate:  age_to_birthdate(child_params[:age]),
                notes:      child_params[:notes].presence
              )
            end
          end

          def build_guardians(family)
            return unless params[:guardians].present?

            params[:guardians].each do |g|
              next if g[:first_name].blank?

              family.guardians.create!(
                first_name:   g[:first_name],
                last_name:    g[:last_name].presence,
                phone:        g[:phone].presence,
                email:        g[:email].presence,
                relationship: g[:relationship].presence
              )
            end
          end

          # Convert age integer to an approximate birthdate (July 1 of birth year).
          # Parents correct the exact date when completing their profile.
          def age_to_birthdate(age)
            return nil if age.blank?
            years = age.to_i
            return nil if years <= 0
            Date.new(Date.current.year - years, 7, 1)
          end

          # Returns "sms", "email", or "none" depending on what was sent.
          # SMS is preferred when Twilio is configured and the family has a phone.
          # Email is the fallback when Twilio is not configured.
          def send_invite(family, invitation)
            if SmsClient.configured? && family.phone.present?
              first = family.primary_contact_first_name.presence || "there"
              body  = "Hi #{first}! Complete your family profile here: " \
                      "#{invitation.invite_url} (link expires in 7 days)"
              SmsClient.send(to: family.phone, body: body)
              "sms"
            elsif family.email.present?
              Spirely::InviteMailer.invite(family, invitation).deliver_later
              "email"
            else
              "none"
            end
          end

          def family_params
            params.require(:family).permit(
              :primary_contact_first_name,
              :primary_contact_last_name,
              :phone,
              :email,
              :address
            )
          end
        end
      end
    end
  end
end
