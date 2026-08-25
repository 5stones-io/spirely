module Spirely
  module Api
    module V1
      class BaseController < ActionController::API
        include TenantResolution

        before_action :require_tenant!
        before_action :authenticate!

        private

        def authenticate!
          unless rodauth.authenticated?
            render json: { error: "Unauthorized", code: "unauthorized" }, status: :unauthorized
            return
          end
          acct_id = rodauth.session[rodauth.session_key]
          Current.account = Account.find_by(id: acct_id)
          # Multi-account family access: an account may be the family's
          # own primary contact (Family#account_id) OR a separately
          # invited Guardian (Guardian#account_id). Both resolve to the
          # same Family from here on, so every other controller that
          # calls current_family works unchanged regardless of which
          # account is signed in — but current_person (below) still
          # needs to know *which specific* guardian this is, not just
          # the family, so @current_guardian is kept separately.
          family_match = Current.account && Spirely::Family.find_by(account_id: acct_id, church_id: Current.church.id)
          @current_guardian =
            if Current.account && family_match.nil?
              Spirely::Guardian.find_by(account_id: acct_id, church_id: Current.church.id)
            end
          @current_family = family_match || @current_guardian&.family
          Current.membership = Current.account && Membership.find_by(account_id: acct_id, church_id: Current.church.id)
        end

        def current_family = @current_family
        def current_guardian = @current_guardian

        # Admin-ness is per-church (Membership.role), not a JWT claim — see
        # rodauth_main.rb for why tenant/role is deliberately resolved fresh
        # on every request instead of baked into the token.
        def admin? = Current.membership&.admin_or_owner? == true

        # Grounded in real PCO-derived signals, not a manually-set flag:
        # either they've been brought into Spirely's own volunteer pipeline
        # and reached Active/Reserve-Bench (VolunteerProfile#pipeline_stage,
        # itself staff-driven from PCO search), or PCO's own Check-Ins data
        # already has them checking in with kind "volunteer" (their real
        # service history, synced via PcoAttendanceSyncJob). Three ways to
        # find the matching Person, tried in order:
        #  1. Guardian#person — a signed-in *second* adult on a family
        #     (multi-account family access), joined by their own
        #     pco_person_id. Real production case that surfaced this was
        #     missing: a guardian with genuine volunteer-kind Attendance
        #     history was being checked against the family's *primary
        #     contact's* Person instead of her own — #current_person used
        #     to fall straight to current_family&.person regardless of
        #     whether the signed-in account was the primary contact or a
        #     separately-invited guardian, so a guardian's own volunteer
        #     status was invisible no matter how much real service history
        #     she had. Checked first since it's the most specific match
        #     when it applies.
        #  2. Family#person — the account's own Family record's primary
        #     contact, joined by shared pco_person_id (see Family#person's
        #     comment — the "Linked Dual-Role Records" gap). More reliable
        #     than email since it's the same hard PCO identity on both
        #     sides, not a string match, and covers the actual dual-role
        #     case this was built for: a parent who's also a volunteer.
        #  3. Fallback: Person matched by email — covers a volunteer with
        #     no Family record at all yet (no kids, never filled out
        #     family info) who wouldn't have a Family#person path.
        # Neither hits PCO live — matches the "on-demand, not nightly
        # batch" timing principle without a network call on every login.
        # Extracted here from MeController (where this logic originated)
        # since other controllers now need the same staff-or-volunteer gate
        # (e.g. ThisWeeksLessonController).
        def volunteer?
          return false unless Current.church&.module_enabled?("kidsmin")

          person = current_person
          return false unless person

          person.volunteer_profile&.stage_reached?("active") ||
            person.attendances.exists?(kind: "volunteer")
        end

        # Extracted from volunteer? above — other staff-or-volunteer-gated
        # controllers (e.g. ThisWeeksLessonController) need the resolved
        # Person itself, not just the yes/no check.
        def current_person
          @current_person ||= current_guardian&.person ||
                               current_family&.person ||
                               Current.church.people.find_by(email: Current.account.email)
        end

        def require_family!
          return if current_family
          render json: { error: "Family profile not found", code: "family_not_found" },
                 status: :not_found
        end

        def require_admin!
          return if admin?
          render json: { error: "Forbidden", code: "forbidden" }, status: :forbidden
        end

        # Ministry modules (kidsmin, future ones) — gated per-church at the
        # controller layer, not a routing difference (see CLAUDE.md's
        # module-toggle reorganization). 404, not 403 — a disabled module
        # isn't "you lack permission," it's "this doesn't exist for this
        # church," same honest-signal reasoning as require_family!'s
        # family_not_found. Independent of role gates (require_admin!,
        # require_family!, etc.) — call both when a controller needs both;
        # order between them doesn't matter, each renders+returns on its
        # own failure.
        def require_module!(name)
          return if Current.church&.module_enabled?(name)
          render json: { error: "This feature isn't enabled for your church", code: "module_disabled" },
                 status: :not_found
        end

        def require_staff_or_volunteer!
          return if admin? || volunteer?
          render json: { error: "Forbidden", code: "forbidden" }, status: :forbidden
        end

        # Family OR staff/volunteer — for a screen every role should be
        # able to at least view (e.g. Upcoming Events), where the personal
        # "my kids" data a family account gets just isn't there for staff.
        def require_family_or_staff!
          return if current_family || admin? || volunteer?
          render json: { error: "Forbidden", code: "forbidden" }, status: :forbidden
        end

        def pagination_meta(collection)
          {
            total_count:  collection.total_count,
            current_page: collection.current_page,
            total_pages:  collection.total_pages,
            per_page:     collection.limit_value
          }
        end
      end
    end
  end
end
