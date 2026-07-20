require "rails_helper"

RSpec.describe Spirely::ChurchIntegration, type: :model do
  before { Spirely.configuration.encryption_key = SecureRandom.hex(32) }

  describe ".current" do
    it "returns a singleton oauth-type record" do
      expect(described_class.current.token_type).to eq("oauth")
    end
  end

  describe "token encryption" do
    it "round-trips access_token through encryption" do
      integration = described_class.new(token_type: "oauth")
      integration.access_token = "plaintext-token"
      expect(integration.access_token).to eq("plaintext-token")
      expect(integration[:access_token]).not_to eq("plaintext-token")
    end
  end

  describe "#update_tokens!" do
    it "sets expires_at from expires_in" do
      integration = described_class.new(token_type: "oauth")
      integration.update_tokens!(access: "a", refresh: "r", expires_in: 3600)
      expect(integration.expires_at).to be_within(5.seconds).of(1.hour.from_now)
      expect(integration.pco_connected?).to be(true)
    end
  end
end
