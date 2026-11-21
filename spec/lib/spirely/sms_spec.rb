require "rails_helper"

RSpec.describe Spirely::Sms do
  describe ".e164" do
    it "adds +1 to a US number however it's written" do
      expect(described_class.e164("(555) 201-3344")).to eq("+15552013344")
      expect(described_class.e164("555.201.3344")).to eq("+15552013344")
      expect(described_class.e164("1-555-201-3344")).to eq("+15552013344")
      expect(described_class.e164("+1 555 201 3344")).to eq("+15552013344")
    end

    it "leaves anything else as it was" do
      expect(described_class.e164("+44 20 7946 0958")).to eq("+44 20 7946 0958")
      expect(described_class.e164("555-0100")).to eq("555-0100")
    end
  end

  it "sends to the +1 form of the number" do
    Spirely.configuration.encryption_key = SecureRandom.hex(32)
    integration = create(:spirely_church_integration, twilio_account_sid: "AC1", twilio_auth_token: "t",
                                                      twilio_from_number: "+15550000000")
    response = instance_double(HTTParty::Response, success?: true, parsed_response: {})
    allow(HTTParty).to receive(:post).and_return(response)

    described_class.new(integration).send(to: "555-201-3344", body: "Hi")
    expect(HTTParty).to have_received(:post).with(anything, hash_including(body: hash_including(To: "+15552013344")))
  end
end
