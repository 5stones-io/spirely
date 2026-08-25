module Spirely
  # Shared SMS+email invite delivery — same priority logic (SMS first if
  # Twilio's configured and a phone is on file, else email, else "none")
  # across every invite flow this app has (family, guardian, staff).
  # Takes first_name/phone/email explicitly rather than a model object
  # since Family/Guardian don't even share attribute names for these
  # (primary_contact_first_name vs first_name) — this is the one place
  # that difference gets normalized. `mailer:` and `sms_purpose:` let a
  # caller vary the actual copy (a staff invite isn't "your family
  # profile") without duplicating the SMS/email priority logic itself.
  class InviteSender
    def self.call(church:, first_name:, phone:, email:, invitation:, mailer: Spirely::InviteMailer, sms_purpose: "Complete your family profile")
      integration = church.church_integration
      methods = []

      # Gated on twilio_verified?, not just twilio_configured? — Twilio
      # accepting an API call doesn't mean a real phone receives it (a
      # real send silently went nowhere due to A2P 10DLC carrier
      # filtering, confirmed 2026-08-09). Verification (Admin::
      # TwilioVerificationController) is the one real proof a specific
      # number actually delivers.
      if integration&.twilio_verified? && phone.present?
        body = "Hi #{first_name.presence || "there"}! #{sms_purpose} here: " \
               "#{invitation.invite_url} (link expires in 7 days)"
        begin
          Spirely::Sms.new(integration).send(to: phone, body: body)
          methods << "sms"
        rescue Spirely::Error => e
          Rails.logger.error("[Spirely] Invite SMS failed for invitation #{invitation.id}: #{e.message}")
        end
      end

      if email.present?
        mailer.invite(church: church, first_name: first_name, email: email, invitation: invitation).deliver_later
        methods << "email"
      end

      methods
    end
  end
end
