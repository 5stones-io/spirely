module Spirely
  # Emails for Create Account (5ST-85, Spirely::AccountRequest).
  class FamilySignupMailer < ApplicationMailer
    # Everyone who uses Create Account gets this, at the email they typed.
    def confirm_email(signup)
      @church = signup.church
      @url = signup.invite_url
      mail(to: signup.email, subject: "Confirm your email for #{@church.name}")
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
