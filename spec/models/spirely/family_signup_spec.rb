require "rails_helper"

# A family asking for an account from the church's site (5ST-85): the
# sign-up they finish, and what approving it creates.
RSpec.describe Spirely::FamilySignup do
  include ActiveJob::TestHelper

  let(:church) { create(:church) }
  let(:signup) { church.family_signups.create!(phone: "(555) 201-3344", email: "Pat@Example.com") }
  let(:details) do
    { "first_name" => "Pat", "last_name" => "Rivera", "address" => "12 Oak St, Springfield",
      "children" => [{ "first_name" => "Mia", "last_name" => "", "birthdate" => "2019-04-02", "allergies" => "Peanuts" },
                     { "first_name" => "Leo", "birthdate" => "2021-09-15" }] }
  end

  after { ActionMailer::Base.deliveries.clear }

  it "keeps the phone's digits and a lowercased email, with a link that lasts a week" do
    expect(signup).to have_attributes(phone: "5552013344", email: "pat@example.com", status: "started")
    expect(signup.token).to be_present
    expect(signup.expires_at).to be_within(1.minute).of(7.days.from_now)
    expect(signup.invite_url).to eq("https://#{church.primary_hostname}/join/#{signup.token}")
  end

  it "needs a 10-digit phone and an email" do
    expect(church.family_signups.new(phone: "555-12", email: "x@example.com")).not_to be_valid
    expect(church.family_signups.new(phone: "5552013344", email: "nope")).not_to be_valid
    expect(church.family_signups.new(phone: "1 555 201 3344", email: "x@example.com")).to be_valid
  end

  describe "#submit!" do
    it "saves the family's details and waits for staff" do
      signup.submit!(details)
      expect(signup.reload).to have_attributes(status: "submitted")
      expect(signup.submitted_at).to be_present
      expect(signup.details["children"].map { |c| c["first_name"] }).to eq(%w[Mia Leo])
    end

    it "needs the parent's name and at least one child" do
      expect { signup.submit!(details.merge("last_name" => "")) }.to raise_error(ActiveRecord::RecordInvalid)
      expect { signup.submit!(details.merge("children" => [])) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(signup.reload.status).to eq("started")
    end

    it "keeps only the fields it knows" do
      signup.submit!(details.merge("admin" => true, "children" => [{ "first_name" => "Mia", "role" => "x" }]))
      expect(signup.details.keys).to contain_exactly("first_name", "last_name", "address", "children")
      expect(signup.details["children"]).to eq([{ "first_name" => "Mia", "last_name" => "", "birthdate" => nil, "allergies" => "" }])
    end
  end

  describe "#approve!" do
    let(:staff) { create(:account) }

    before { signup.submit!(details) }

    it "creates the family and its kids, and emails the normal invite" do
      family = perform_enqueued_jobs { signup.approve!(by: staff) }

      expect(family).to have_attributes(church: church, family_name: "Rivera Family", primary_contact_first_name: "Pat",
                                        phone: "5552013344", email: "pat@example.com", address: "12 Oak St, Springfield")
      expect(family.children.map { |c| [c.first_name, c.last_name, c.birthdate.to_s] })
        .to contain_exactly(["Mia", "Rivera", "2019-04-02"], ["Leo", "Rivera", "2021-09-15"])
      expect(family.children.find_by(first_name: "Mia").allergy_notes).to eq("Peanuts")
      expect(signup.reload).to have_attributes(status: "approved", family: family, reviewed_by_account_id: staff.id)
      expect(family.invitations.active.count).to eq(1)
      expect(ActionMailer::Base.deliveries.map(&:to)).to eq([["pat@example.com"]])
    end

    it "texts the invite too once the church's texting is verified" do
      Spirely.configuration.encryption_key = SecureRandom.hex(32)
      create(:spirely_church_integration, church: church, twilio_account_sid: "AC1", twilio_auth_token: "t",
                                          twilio_from_number: "+15550000000", twilio_verified_at: Time.current)
      sms = instance_double(Spirely::Sms, send: {})
      allow(Spirely::Sms).to receive(:new).and_return(sms)

      signup.approve!(by: staff)
      expect(sms).to have_received(:send).with(to: "5552013344", body: a_string_including("/invite/"))
    end

    it "won't approve twice, or one that isn't finished" do
      signup.approve!(by: staff)
      expect { signup.approve!(by: staff) }.to raise_error(Spirely::FamilySignup::NotPending)
      started = church.family_signups.create!(phone: "5550001111", email: "a@example.com")
      expect { started.approve!(by: staff) }.to raise_error(Spirely::FamilySignup::NotPending)
    end
  end

  describe "#decline!" do
    it "closes it without creating a family" do
      signup.submit!(details)
      signup.decline!(by: create(:account))
      expect(signup.reload.status).to eq("declined")
      expect(church.families).to be_empty
    end
  end
end
