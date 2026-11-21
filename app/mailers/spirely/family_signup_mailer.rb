module Spirely
  # Emails for Create Account (5ST-85, Spirely::AccountRequest).
  class FamilySignupMailer < ApplicationMailer
    # The link to the new-family form. Named and shaped like
    # InviteMailer#invite so InviteSender can send it (and text it).
    def invite(church:, first_name:, email:, invitation:)
      @church = church
      @url = invitation.invite_url
      mail(to: email, subject: "Finish signing up your family with #{church.name}")
    end

    # Someone used Create Account but already has an account.
    def already_has_account(church:, first_name:, email:)
      @church = church
      @first_name = first_name.presence || "there"
      @url = "https://#{church.primary_hostname}/login"
      mail(to: email, subject: "You already have an account with #{church.name}")
    end

    # To each admin and owner: a new family is waiting for approval.
    def submitted(signup, to)
      @signup = signup
      @church = signup.church
      @name = "#{signup.details["first_name"]} #{signup.details["last_name"]}".strip
      @url = "https://#{@church.primary_hostname}/families?signups=1"
      mail(to: to, subject: "New family waiting for approval: #{@name}")
    end
  end
end
