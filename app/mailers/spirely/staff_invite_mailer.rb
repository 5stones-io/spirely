module Spirely
  class StaffInviteMailer < ApplicationMailer
    # Same shape as InviteMailer.invite (church:/first_name:/email:/
    # invitation:) so InviteSender can call either one interchangeably —
    # different copy only, "staff console" not "family portal".
    def invite(church:, first_name:, email:, invitation:)
      @church     = church
      @invite_url = invitation.invite_url
      @first_name = first_name.presence || "there"

      mail(
        to:      email,
        subject: "You're invited to join #{church.name}'s staff team on Spirely"
      )
    end
  end
end
