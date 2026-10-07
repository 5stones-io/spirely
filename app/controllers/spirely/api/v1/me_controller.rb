module Spirely
  module Api
    module V1
      # Resolves which portal landing page a logged-in account should see —
      # Children's Pastor/Staff, Volunteer, or Parent (product spec's Roles
      # & Access section; "Kids" is deliberately excluded, see the same
      # section — an open question there, assumed kiosk-based rather than a
      # real login).
      class MeController < BaseController
        def show
          render json: {
            email: Current.account.email,
            # Threaded through for the Profile page (5ST-42) — falls back to
            # email client-side same as every other name display since this
            # is blank for a pending invite's not-yet-accepted account (see
            # Account#name).
            name: Current.account.name,
            phone: Current.account.phone,
            church_name: Current.church.name,
            role: role,
            # Staff-only "preview as" switcher (Landing.tsx) — lets a real
            # staff account click through the Volunteer/Parent screens for
            # QA/support/demoing without a separate test account. Gated on
            # Church#role_preview_enabled (off by default, toggled per
            # church via console for now, same as session_recording_enabled)
            # so it stays invisible everywhere until explicitly turned on,
            # and on admin? here so a non-staff account is never told it
            # exists even if the church has it enabled.
            role_preview_enabled: admin? && Current.church.role_preview_enabled?,
            # Which ministry modules this church has on (Church::MODULES) —
            # the frontend gates navigation and screens on this.
            enabled_modules: Current.church.enabled_modules,
            # Every role this account holds here, not just the single
            # highest-priority `role` above — e.g. an admin who's also a
            # parent gets ["staff", "parent"]. `role` still decides the
            # landing page; this lets other screens offer extra entry
            # points (e.g. Small Groups' "My Groups").
            capabilities: capabilities,
          }
        end

        private

        # Priority order: Staff > Volunteer > Parent. An account can match
        # more than one (e.g. an admin who's also a parent) — staff wins as
        # the most privileged, real signal. nil when none apply.
        def role
          return "staff" if admin?
          return "volunteer" if volunteer?
          return "parent" if Current.membership&.role == "family"

          nil
        end

        # Same priority order as `role`. "parent" here also covers an
        # account that has a family (own or as a guardian) but whose one
        # Membership row is admin — `role` can't express that, this can.
        def capabilities
          @capabilities ||= [
            ("staff" if admin?),
            ("volunteer" if volunteer?),
            ("parent" if Current.membership&.role == "family" || current_family),
          ].compact
        end
      end
    end
  end
end
