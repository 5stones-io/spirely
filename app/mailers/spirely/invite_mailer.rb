module Spirely
  class InviteMailer < ApplicationMailer
    # Generic over *who's* being invited (the family's own primary
    # contact, or — for multi-account family access — a specific
    # Guardian) rather than assuming a Family object, since the actual
    # recipient's name/email differ per case but the email itself is
    # otherwise identical either way.
    def invite(church:, first_name:, email:, invitation:)
      @church     = church
      @invite_url = invitation.invite_url
      @first_name = first_name.presence || "there"

      mail(
        to:      email,
        subject: "You're invited to join #{church.name}'s family portal!"
      )
    end
  end
end
