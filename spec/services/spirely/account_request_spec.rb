require "rails_helper"

# Create Account on the church's site (5ST-85): a parent gives a phone and
# an email, and gets the same "confirm your email" link at the email they
# typed whoever they are. We only look them up once they've opened it
# (FamilySignup#confirm!), so neither the page nor what lands in their
# inbox says whether a family is on file.
RSpec.describe Spirely::AccountRequest do
  include ActiveJob::TestHelper

  let(:church) { create(:church) }

  def request!(phone: "(555) 201-3344", email: "typed@example.com")
    perform_enqueued_jobs { described_class.call(church: church, phone: phone, email: email) }
  end

  def mail_to = ActionMailer::Base.deliveries.map(&:to).flatten
  def last_mail = ActionMailer::Base.deliveries.last
  def last_body = last_mail.text_part.body.to_s

  after { ActionMailer::Base.deliveries.clear }

  it "emails a link to confirm the email typed" do
    request!
    signup = church.family_signups.sole
    expect(signup).to have_attributes(phone: "5552013344", email: "typed@example.com", status: "started",
                                      email_confirmed_at: nil)
    expect(mail_to).to eq(["typed@example.com"])
    expect(last_mail.subject).to include("Confirm your email")
    expect(last_body).to include(signup.invite_url)
  end

  it "sends exactly the same thing when the phone or email is a family's on file, and nothing to the family" do
    request!(phone: "5550000000", email: "stranger@example.com")
    unknown = last_body.gsub(%r{/join/\S+}, "")

    create(:spirely_family, church: church, account: nil, phone: "5552013344", email: "onfile@example.com")
    create(:spirely_family, church: church, phone: "5553334444", email: "hasaccount@example.com")
    ActionMailer::Base.deliveries.clear

    request!(phone: "5552013344", email: "typed@example.com")
    request!(phone: "5553334444", email: "hasaccount@example.com")

    expect(mail_to).to eq(["typed@example.com", "hasaccount@example.com"])
    expect(ActionMailer::Base.deliveries.map { |m| m.text_part.body.to_s.gsub(%r{/join/\S+}, "") }.uniq).to eq([unknown])
    expect(Spirely::Invitation.count).to eq(0)
  end

  it "doesn't text, even once the church's texting is verified" do
    Spirely.configuration.encryption_key = SecureRandom.hex(32)
    create(:spirely_church_integration, church: church, twilio_account_sid: "AC1", twilio_auth_token: "t",
                                        twilio_from_number: "+15550000000", twilio_verified_at: Time.current)
    allow(Spirely::Sms).to receive(:new)
    request!
    expect(Spirely::Sms).not_to have_received(:new)
  end

  it "sends the same link again rather than starting another sign-up" do
    request!
    request!
    expect(church.family_signups.count).to eq(1)
    expect(mail_to).to eq(["typed@example.com", "typed@example.com"])
  end

  it "starts a new one once the old link has expired" do
    request!
    church.family_signups.sole.update!(expires_at: 1.minute.ago)
    request!
    expect(church.family_signups.count).to eq(2)
  end

  it "rejects a phone or email that isn't one" do
    expect { described_class.call(church: church, phone: "123", email: "a@example.com") }.to raise_error(ActiveRecord::RecordInvalid)
    expect { described_class.call(church: church, phone: "5552013344", email: "nope") }.to raise_error(ActiveRecord::RecordInvalid)
    expect(church.family_signups.count).to eq(0)
    expect(ActionMailer::Base.deliveries).to be_empty
  end
end
