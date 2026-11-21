require "rails_helper"

# Create Account on the church's site (5ST-85): a parent gives a phone and
# an email, and we work out what to send them. Invites to a family we
# already have only ever go to the contact details on file.
RSpec.describe Spirely::AccountRequest do
  include ActiveJob::TestHelper

  let(:church) { create(:church) }

  def request!(phone: "(555) 201-3344", email: "typed@example.com")
    perform_enqueued_jobs { described_class.call(church: church, phone: phone, email: email) }
  end

  def mail_to = ActionMailer::Base.deliveries.map(&:to).flatten
  def last_body = ActionMailer::Base.deliveries.last.text_part.body.to_s

  after { ActionMailer::Base.deliveries.clear }

  context "with a family on file that has no account yet" do
    let!(:family) { create(:spirely_family, church: church, account: nil, phone: "555.201.3344", email: "onfile@example.com") }

    it "emails the normal invite to the email on file, not the one typed" do
      request!
      expect(mail_to).to eq(["onfile@example.com"])
      expect(last_body).to include(family.invitations.active.sole.invite_url)
      expect(church.family_signups).to be_empty
    end

    it "finds them by the email on file too" do
      request!(phone: "5559999999", email: "OnFile@example.com")
      expect(mail_to).to eq(["onfile@example.com"])
      expect(family.invitations.active.count).to eq(1)
    end

    it "replaces an older invite that wasn't used" do
      old = family.invitations.create!
      request!
      expect(old.reload.expired?).to be(true)
      expect(family.invitations.active.count).to eq(1)
    end

    it "sends a new-family link instead when there's no email on file to use, and notes the likely match" do
      family.update!(email: nil)
      request!
      signup = church.family_signups.sole
      expect(signup).to have_attributes(phone: "5552013344", email: "typed@example.com", matched_family: family)
      expect(mail_to).to eq(["typed@example.com"])
      expect(last_body).to include(signup.invite_url)
      expect(family.invitations).to be_empty
    end
  end

  it "invites a second parent on file as themselves" do
    family = create(:spirely_family, church: church, phone: "5550001111")
    guardian = create(:spirely_guardian, family: family, church: church, phone: "555-201-3344", email: "dad@example.com")
    request!
    expect(mail_to).to eq(["dad@example.com"])
    expect(family.invitations.active.sole.guardian).to eq(guardian)
  end

  it "tells someone who already has an account to sign in, at the email on file" do
    create(:spirely_family, church: church, phone: "5552013344", email: "onfile@example.com")
    request!
    expect(mail_to).to eq(["onfile@example.com"])
    expect(last_body).to include("already have an account").and include("/login")
    expect(Spirely::Invitation.count).to eq(0)
    expect(church.family_signups).to be_empty
  end

  context "when we don't know them" do
    it "emails a link to the new-family form, to the email typed" do
      request!
      signup = church.family_signups.sole
      expect(signup).to have_attributes(phone: "5552013344", email: "typed@example.com", status: "started", matched_family: nil)
      expect(mail_to).to eq(["typed@example.com"])
      expect(last_body).to include(signup.invite_url)
    end

    it "texts the link too once the church's texting is verified" do
      Spirely.configuration.encryption_key = SecureRandom.hex(32)
      create(:spirely_church_integration, church: church, twilio_account_sid: "AC1", twilio_auth_token: "t",
                                          twilio_from_number: "+15550000000", twilio_verified_at: Time.current)
      sms = instance_double(Spirely::Sms, send: {})
      allow(Spirely::Sms).to receive(:new).and_return(sms)
      request!
      expect(sms).to have_received(:send).with(to: "5552013344", body: a_string_including("/join/"))
    end

    it "sends the same link again rather than starting another sign-up" do
      request!
      request!
      expect(church.family_signups.count).to eq(1)
      expect(mail_to).to eq(["typed@example.com", "typed@example.com"])
    end

    it "doesn't match another church's families" do
      create(:spirely_family, church: create(:church), account: nil, phone: "5552013344", email: "elsewhere@example.com")
      request!
      expect(mail_to).to eq(["typed@example.com"])
      expect(church.family_signups.count).to eq(1)
    end
  end

  it "rejects a phone or email that isn't one" do
    expect { described_class.call(church: church, phone: "123", email: "a@example.com") }.to raise_error(ActiveRecord::RecordInvalid)
    expect { described_class.call(church: church, phone: "5552013344", email: "nope") }.to raise_error(ActiveRecord::RecordInvalid)
    expect(church.family_signups.count).to eq(0)
    expect(ActionMailer::Base.deliveries).to be_empty
  end
end
