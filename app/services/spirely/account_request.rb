module Spirely
  # Create Account on the church's site (5ST-85). A parent gives a phone and
  # an email; we look for them among the church's families and guardians
  # (synced from Planning Center or added by staff) and send one of:
  #
  # - the normal invite, when we find someone without an account. It goes
  #   only to the email and phone ON FILE, never to what was typed, or anyone
  #   could type a known family's phone with their own email and get into
  #   that family's records.
  # - a "you already have an account" email (to the email on file).
  # - a link to the new-family form (Spirely::FamilySignup), to what was
  #   typed, when we don't find them, or find them with no email on file to
  #   use. Staff approve those, and see the likely match.
  #
  # Texts go out alongside email once the church's texting is verified
  # (InviteSender). The caller answers the same in every case, so the page
  # can't be used to learn who's in the church's records.
  class AccountRequest
    def self.call(church:, phone:, email:) = new(church, phone, email).call

    def initialize(church, phone, email)
      @church = church
      probe = Spirely::FamilySignup.new(church: church, phone: phone, email: email)
      probe.validate!
      @phone = probe.phone
      @email = probe.email
    end

    def call
      person = family_on_file || guardian_on_file

      if person.nil?
        send_signup_link(nil)
      elsif person.account_id
        already_has_account(person)
      elsif reachable?(person)
        send_invite(person)
      else
        send_signup_link(family_of(person))
      end
      nil
    end

    private

    attr_reader :church, :phone, :email

    PHONE_DIGITS = "right(regexp_replace(coalesce(%s, ''), '\\D', '', 'g'), 10)"

    def family_on_file
      church.families
            .where("#{format(PHONE_DIGITS, "phone")} = :phone OR lower(email) = :email", phone: phone, email: email)
            .order(:id).first
    end

    def guardian_on_file
      Spirely::Guardian.joins(:family).where(spirely_families: { church_id: church.id })
                       .where("#{format(PHONE_DIGITS, "spirely_guardians.phone")} = :phone OR lower(spirely_guardians.email) = :email",
                              phone: phone, email: email)
                       .order(:id).first
    end

    def family_of(person) = person.is_a?(Spirely::Guardian) ? person.family : person

    def first_name_of(person)
      person.is_a?(Spirely::Guardian) ? person.first_name : person.primary_contact_first_name
    end

    def texting? = church.church_integration&.twilio_verified?

    def reachable?(person)
      person.email.present? || (texting? && person.phone.present?)
    end

    def send_invite(person)
      family = family_of(person)
      guardian = person.is_a?(Spirely::Guardian) ? person : nil
      family.invitations.where(guardian: guardian, accepted_at: nil).update_all(expires_at: Time.current)
      invitation = family.invitations.create!(guardian: guardian)
      Spirely::InviteSender.call(church: church, first_name: first_name_of(person),
                                 phone: person.phone, email: person.email, invitation: invitation)
    end

    def already_has_account(person)
      return if person.email.blank?

      Spirely::FamilySignupMailer.already_has_account(church: church, first_name: first_name_of(person),
                                                      email: person.email).deliver_later
    end

    # Reuses a sign-up this phone and email already started, so asking twice
    # sends the same link.
    def send_signup_link(matched_family)
      signup = church.family_signups.where(phone: phone, email: email)
                     .where("status = 'submitted' OR (status = 'started' AND expires_at > ?)", Time.current)
                     .order(:id).last
      signup ||= church.family_signups.create!(phone: phone, email: email)
      signup.update!(matched_family: matched_family) if matched_family && signup.matched_family_id.nil?

      Spirely::InviteSender.call(church: church, first_name: nil, phone: phone, email: email, invitation: signup,
                                 mailer: Spirely::FamilySignupMailer, sms_purpose: "Finish signing up your family")
    end
  end
end
