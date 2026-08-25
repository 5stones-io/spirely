require "rails_helper"

RSpec.describe Spirely::ChurchIntegration, type: :model do
  before { Spirely.configuration.encryption_key = SecureRandom.hex(32) }

  describe "token encryption" do
    it "round-trips access_token through encryption" do
      integration = build(:spirely_church_integration)
      integration.access_token = "plaintext-token"
      expect(integration.access_token).to eq("plaintext-token")
      expect(integration[:access_token]).not_to eq("plaintext-token")
    end
  end

  describe "#update_tokens!" do
    it "sets expires_at from expires_in" do
      integration = create(:spirely_church_integration)
      integration.update_tokens!(access: "a", refresh: "r", expires_in: 3600)
      expect(integration.expires_at).to be_within(5.seconds).of(1.hour.from_now)
      expect(integration.pco_connected?).to be(true)
    end
  end

  describe "#personal_token?" do
    it "is true only for token_type personal" do
      expect(build(:spirely_church_integration, token_type: "personal")).to be_personal_token
      expect(build(:spirely_church_integration, token_type: "oauth")).not_to be_personal_token
    end
  end

  describe "#twilio_verified?" do
    it "is false until twilio_verified_at is set, and resets when credentials change" do
      integration = create(:spirely_church_integration,
        twilio_account_sid: "sid", twilio_auth_token: "tok", twilio_from_number: "+15551234567",
        twilio_verified_at: Time.current)
      expect(integration).to be_twilio_verified

      integration.update!(twilio_auth_token: "new-tok")
      expect(integration.reload).not_to be_twilio_verified
    end
  end
end
