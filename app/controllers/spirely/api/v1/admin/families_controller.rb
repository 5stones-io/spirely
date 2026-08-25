module Spirely
  module Api
    module V1
      module Admin
        class FamiliesController < BaseController
          before_action :require_admin!

          # GET /api/v1/admin/families?status=active|inactive&search=becca
          def index
            scope = Current.church.families.with_children
            scope = params[:status] == "inactive" ? scope.attendance_inactive : scope.attendance_active
            scope = scope.search(params[:search]) if params[:search].present?

            families = scope.includes(:children, :guardians, :account)
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
                  # Every other adult in the household — Chad's ask,
                  # so the list view itself shows the whole household
                  # before expanding to kids, not just the one PCO
                  # designates the primary contact.
                  guardian_names:             f.guardians.map { |g| "#{g.first_name} #{g.last_name}".strip },
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
            family = Current.church.families.includes(:children, :guardians, :account).find(params[:id])
            # guardian_id: nil scopes this to the family's own primary-
            # contact invite specifically — a guardian-scoped invite
            # (multi-account family access) also belongs_to :family, so
            # without this a more-recently-sent guardian invite could
            # shadow the family's own pending invite_url here.
            pending_invite = family.invitations.where(accepted_at: nil, guardian_id: nil)
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
                  grade_display: c.grade_display, age: c.age, notes: c.notes,
                  allergy_summary: c.allergy_summary, allergy_updated_at: c.allergy_updated_at }
              },
              guardians:  family.guardians.map { |g|
                { id: g.id, first_name: g.first_name, last_name: g.last_name,
                  phone: g.phone, email: g.email, relationship: g.relationship,
                  account_linked: g.account_id.present?,
                  # Lets the UI offer a direct "Add as Volunteer" action
                  # right from this row — pco_person_id is what
                  # POST /admin/volunteer_profiles actually needs (same
                  # endpoint the PCO-search "+ Add Volunteer" flow
                  # already uses), nil for a Quick-Add-only guardian with
                  # no PCO identity to seed a profile from.
                  pco_person_id: g.pco_person_id,
                  is_volunteer:  g.person&.volunteer_profile.present? }
              },
              invite_url: pending_invite&.invite_url,
            }
          end

          # POST /api/v1/admin/families/:id/invite
          def invite
            family = Current.church.families.find(params[:id])

            family.invitations.where(accepted_at: nil).update_all(expires_at: Time.current)

            invitation     = family.invitations.create!
            invite_methods = send_invite(family, invitation)

            render json: { invite_url: invitation.invite_url, invite_methods: invite_methods }
          end

          # POST /api/v1/admin/families
          def create
            if family_params[:address].blank?
              return render json: { error: "Home address is required", code: "validation_error" },
                            status: :unprocessable_entity
            end

            family = build_family
            family.save!

            build_children(family)
            build_guardians(family)

            invitation     = family.invitations.create!
            invite_methods = send_invite(family, invitation)

            pco_connected   = Current.church.church_integration&.pco_connected? &&
                              (Current.church.church_integration.expires_at.nil? ||
                               Current.church.church_integration.expires_at > Time.current)
            PcoCreatePersonJob.perform_later(family.id) if pco_connected

            render json: {
              family:          FamilyBlueprint.render_as_hash(family, view: :with_children),
              invite_url:      invitation.invite_url,
              invite_methods:  invite_methods, # any of "sms", "email" — both sent when both are available
              sms_sent:        invite_methods.include?("sms"),
              email_sent:      invite_methods.include?("email"),
              pco_sync_queued: pco_connected,
            }, status: :created

          rescue ActiveRecord::RecordInvalid => e
            render json: { error: e.message, code: "validation_error" },
                   status: :unprocessable_entity
          end

          private

          def build_family
            p = family_params
            family_name = "#{p[:primary_contact_last_name]} Family"

            Current.church.families.new(
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

          def age_to_birthdate(age)
            return nil if age.blank?
            years = age.to_i
            return nil if years <= 0
            Date.new(Date.current.year - years, 7, 1)
          end

          # Returns which of "sms"/"email" actually went out — both, when
          # both a phone (with Twilio configured) and an email are on
          # file, not one-or-the-other. Belt-and-suspenders: Twilio
          # accepting a send only means PCO/Twilio queued it, not that it
          # actually reached the phone (carrier-side filtering — e.g. a
          # number not yet A2P 10DLC registered — happens silently and
          # asynchronously, with nothing for this app to check in real
          # time), so email going out too gives the family a working
          # fallback rather than a single point of failure. "sms" is only
          # included on an actual successful Twilio API accept — a raised
          # Spirely::Error is logged, not counted as sent. The
          # invite_url is always in the response either way, so staff can
          # hand it over directly regardless of what did or didn't land.
          def send_invite(family, invitation)
            Spirely::InviteSender.call(
              church:     Current.church,
              first_name: family.primary_contact_first_name,
              phone:      family.phone,
              email:      family.email,
              invitation: invitation
            )
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
