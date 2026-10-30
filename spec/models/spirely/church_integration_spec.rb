require "rails_helper"

RSpec.describe Spirely::ChurchIntegration, type: :model do
  before { Spirely.configuration.encryption_key = SecureRandom.hex(32) }

  it "belongs to a church" do
    expect(build(:spirely_church_integration, church: nil)).not_to be_valid
  end

  describe "#pco_app_configured?" do
    it "is false with no client credentials" do
      integration = build(:spirely_church_integration)
      expect(integration.pco_app_configured?).to be(false)
    end

    it "is true once both client_id and client_secret are set" do
      integration = build(:spirely_church_integration, pco_client_id: "abc", pco_client_secret: "shh")
      expect(integration.pco_app_configured?).to be(true)
    end
  end

  describe "#access_token" do
    it "round-trips through encryption" do
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

  describe "#pco_client_secret" do
    it "round-trips through encryption" do
      integration = described_class.new(church: create(:church), token_type: "oauth")
      integration.pco_client_secret = "super-secret"
      expect(integration.pco_client_secret).to eq("super-secret")
      expect(integration[:pco_client_secret]).not_to eq("super-secret")
    end
  end

  describe "#pco_pat_secret" do
    it "round-trips through encryption" do
      integration = described_class.new(church: create(:church), token_type: "personal")
      integration.pco_pat_secret = "super-secret"
      expect(integration.pco_pat_secret).to eq("super-secret")
      expect(integration[:pco_pat_secret]).not_to eq("super-secret")
    end
  end

  describe "#pco_connected? / #pco_app_configured? — token_type branching" do
    it "OAuth mode: connected requires a real access_token, not just client_id/secret" do
      integration = build(:spirely_church_integration, token_type: "oauth",
        pco_client_id: "abc", pco_client_secret: "shh")
      expect(integration.pco_app_configured?).to be(true)
      expect(integration.pco_connected?).to be(false)

      integration.access_token = "tok"
      expect(integration.pco_connected?).to be(true)
    end

    it "personal mode: connected as soon as app_id/secret are both saved, no separate handshake" do
      integration = build(:spirely_church_integration, token_type: "personal",
        pco_pat_app_id: "app123", pco_pat_secret: "shh")
      expect(integration.pco_app_configured?).to be(true)
      expect(integration.pco_connected?).to be(true)
    end

    it "personal mode: not configured/connected with only one of app_id/secret set" do
      integration = build(:spirely_church_integration, token_type: "personal", pco_pat_app_id: "app123")
      expect(integration.pco_app_configured?).to be(false)
      expect(integration.pco_connected?).to be(false)
    end

    it "saved OAuth credentials don't count while in personal mode, and vice versa" do
      integration = build(:spirely_church_integration, token_type: "personal",
        pco_client_id: "abc", pco_client_secret: "shh")
      expect(integration.pco_app_configured?).to be(false)
    end
  end

  describe "#twilio_configured?" do
    it "is false with no Twilio credentials" do
      expect(build(:spirely_church_integration).twilio_configured?).to be(false)
    end

    it "is false if any one of the three fields is missing" do
      integration = build(:spirely_church_integration, twilio_account_sid: "AC1", twilio_from_number: "+15550100")
      expect(integration.twilio_configured?).to be(false)
    end

    it "is true once account_sid, auth_token, and from_number are all set" do
      integration = build(:spirely_church_integration,
        twilio_account_sid: "AC1", twilio_auth_token: "shh", twilio_from_number: "+15550100")
      expect(integration.twilio_configured?).to be(true)
    end
  end

  describe "#twilio_verified?" do
    it "is false until twilio_verified_at is set" do
      integration = build(:spirely_church_integration,
        twilio_account_sid: "AC1", twilio_auth_token: "shh", twilio_from_number: "+15550100")
      expect(integration.twilio_verified?).to be(false)
    end

    it "can be saved as verified on first creation (e.g. a backfill), unaffected by the reset-on-change guard" do
      integration = create(:spirely_church_integration,
        twilio_account_sid: "AC1", twilio_auth_token: "shh", twilio_from_number: "+15550100",
        twilio_verified_at: Time.current)
      expect(integration.reload.twilio_verified?).to be(true)
    end

    it "resets to unverified when the account_sid changes on an already-saved integration" do
      integration = create(:spirely_church_integration,
        twilio_account_sid: "AC1", twilio_auth_token: "shh", twilio_from_number: "+15550100",
        twilio_verified_at: Time.current)

      integration.update!(twilio_account_sid: "AC2")

      expect(integration.reload.twilio_verified?).to be(false)
    end

    it "resets to unverified when the auth_token changes on an already-saved integration" do
      integration = create(:spirely_church_integration,
        twilio_account_sid: "AC1", twilio_auth_token: "shh", twilio_from_number: "+15550100",
        twilio_verified_at: Time.current)

      integration.update!(twilio_auth_token: "new-tok")

      expect(integration.reload.twilio_verified?).to be(false)
    end

    it "resets to unverified when the from_number changes on an already-saved integration" do
      integration = create(:spirely_church_integration,
        twilio_account_sid: "AC1", twilio_auth_token: "shh", twilio_from_number: "+15550100",
        twilio_verified_at: Time.current)

      integration.update!(twilio_from_number: "+15550199")

      expect(integration.reload.twilio_verified?).to be(false)
    end

    it "stays verified through an unrelated update (e.g. saving PCO credentials)" do
      integration = create(:spirely_church_integration,
        twilio_account_sid: "AC1", twilio_auth_token: "shh", twilio_from_number: "+15550100",
        twilio_verified_at: Time.current)

      integration.update!(pco_client_id: "abc")

      expect(integration.reload.twilio_verified?).to be(true)
    end
  end

  describe "#twilio_auth_token" do
    it "round-trips through encryption" do
      integration = described_class.new(church: create(:church), token_type: "oauth")
      integration.twilio_auth_token = "super-secret"
      expect(integration.twilio_auth_token).to eq("super-secret")
      expect(integration[:twilio_auth_token]).not_to eq("super-secret")
    end
  end

  describe "per-church isolation" do
    it "each church has its own independent credentials" do
      church_a = create(:spirely_church_integration, pco_client_id: "church-a-id", pco_client_secret: "a-secret")
      church_b = create(:spirely_church_integration, pco_client_id: "church-b-id", pco_client_secret: "b-secret")

      expect(church_a.pco_client_id).to eq("church-a-id")
      expect(church_b.pco_client_id).to eq("church-b-id")
      expect(church_a.pco_client_secret).not_to eq(church_b.pco_client_secret)
    end
  end
end
