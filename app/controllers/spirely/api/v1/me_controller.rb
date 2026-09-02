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
          }
        end

        private

        # Priority order: Staff > Volunteer > Parent. An account could
        # technically match more than one (e.g. an admin who's also a
        # parent) — staff wins as the most privileged, real signal.
        def role
          return "staff" if admin?
          return "volunteer" if volunteer?
          return "parent" if Current.membership&.role == "family"

          nil
        end
      end
    end
  end
end
