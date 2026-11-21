module Spirely
  # Create Account on the church's site (5ST-85). A parent gives a phone and
  # an email, and we email a "confirm your email" link to the email typed.
  # Everyone gets the same email, whether or not they're on file: we only
  # look them up once they've opened it (FamilySignup#confirm!), so neither
  # the page nor anyone's inbox says who's in the church's records.
  #
  # Email only: the link proves they own the email. Texts come later, from
  # whatever the link leads to (their invite, once staff approve them).
  class AccountRequest
    def self.call(church:, phone:, email:) = new(church, phone, email).call

    def initialize(church, phone, email)
      @church = church
      probe = Spirely::FamilySignup.new(church: church, phone: phone, email: email)
      probe.validate!
      @phone = probe.phone
      @email = probe.email
    end

    # Asking again sends the same link while it's still good.
    def call
      signup = church.family_signups.where(phone: phone, email: email, status: "started")
                     .where("expires_at > ?", Time.current).order(:id).last
      signup ||= church.family_signups.create!(phone: phone, email: email)
      Spirely::FamilySignupMailer.confirm_email(signup).deliver_later
      nil
    end

    private

    attr_reader :church, :phone, :email
  end
end
