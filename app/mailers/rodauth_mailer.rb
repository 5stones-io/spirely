class RodauthMailer < ApplicationMailer
  def email_auth(email, magic_link_url)
    @magic_link_url = magic_link_url
    mail(to: email, subject: "Your spirely sign-in link")
  end
end
