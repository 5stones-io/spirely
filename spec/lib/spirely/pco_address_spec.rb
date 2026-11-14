require "rails_helper"

RSpec.describe Spirely::PcoAddress do
  describe ".parse" do
    it "splits a Quick-Add address with the state and zip as separate parts" do
      expect(described_class.parse("10718 John Turley Pl, Fairfax, VA, 22032")).to eq(
        street_line_1: "10718 John Turley Pl", city: "Fairfax", state: "VA", zip: "22032"
      )
    end

    it "splits the street, city, ST zip form inbound sync writes" do
      expect(described_class.parse("1 Main St, Fairfax, va 22032-3120")).to eq(
        street_line_1: "1 Main St", city: "Fairfax", state: "VA", zip: "22032-3120"
      )
    end

    it "keeps an address that doesn't split as the street, whole" do
      expect(described_class.parse("Apt 4 above the bakery")).to eq(street_line_1: "Apt 4 above the bakery")
    end

    it "returns nil for a blank address" do
      expect(described_class.parse("  ")).to be_nil
    end
  end

  describe ".format" do
    it "joins PCO's street lines, city, state and zip" do
      record = { "attributes" => { "street_line_1" => "10718 John Turley Pl", "street_line_2" => "Unit 2",
                                   "city" => "Fairfax", "state" => "VA", "zip" => "22032-3120" } }
      expect(described_class.format(record)).to eq("10718 John Turley Pl Unit 2, Fairfax, VA 22032-3120")
    end

    it "falls back to the old street attribute" do
      record = { "attributes" => { "street" => "1 Main St", "city" => "Fairfax", "state" => "VA", "zip" => "22032" } }
      expect(described_class.format(record)).to eq("1 Main St, Fairfax, VA 22032")
    end
  end

  describe ".push" do
    let(:church) { create(:church) }
    let(:client) do
      Spirely.configuration.encryption_key = SecureRandom.hex(32)
      Spirely::PcoClient.new(create(:spirely_church_integration, church: church, access_token: "tok"))
    end
    let(:path) { "https://api.planningcenteronline.com/people/v2/people/p-1/addresses" }

    def stub_addresses(data)
      stub_request(:get, path).with(query: hash_including({}))
        .to_return(status: 200, body: { data: data }.to_json, headers: { "Content-Type" => "application/json" })
    end

    it "adds a primary Home address when the person has none" do
      stub_addresses([])
      stub_request(:post, path).to_return(status: 201, body: { data: { id: "a-1" } }.to_json,
                                          headers: { "Content-Type" => "application/json" })

      described_class.push(client, "p-1", "10718 John Turley Pl, Fairfax, VA, 22032")

      expect(WebMock).to have_requested(:post, path).with(body: hash_including("data" => hash_including(
        "attributes" => { "street_line_1" => "10718 John Turley Pl", "city" => "Fairfax", "state" => "VA",
                          "zip" => "22032", "location" => "Home", "primary" => true }
      )))
    end

    it "updates the primary address when it differs" do
      stub_addresses([{ "id" => "a-1", "attributes" => { "street_line_1" => "Old Rd", "city" => "Reston",
                                                         "state" => "VA", "zip" => "20190", "primary" => true } }])
      stub_request(:patch, "#{path}/a-1").to_return(status: 200, body: { data: { id: "a-1" } }.to_json,
                                                    headers: { "Content-Type" => "application/json" })

      described_class.push(client, "p-1", "10718 John Turley Pl, Fairfax, VA 22032")

      expect(WebMock).to have_requested(:patch, "#{path}/a-1")
    end

    it "leaves an address that already matches alone" do
      stub_addresses([{ "id" => "a-1", "attributes" => { "street_line_1" => "1 Main St", "city" => "Fairfax",
                                                         "state" => "VA", "zip" => "22032", "primary" => true } }])

      described_class.push(client, "p-1", "1 Main St, Fairfax, VA 22032")

      expect(WebMock).not_to have_requested(:patch, /addresses/)
      expect(WebMock).not_to have_requested(:post, /addresses/)
    end

    it "logs instead of raising when PCO rejects the address" do
      stub_addresses([])
      stub_request(:post, path).to_return(status: 422, body: { errors: [{ detail: "invalid" }] }.to_json,
                                          headers: { "Content-Type" => "application/json" })

      expect { described_class.push(client, "p-1", "1 Main St, Fairfax, VA 22032") }.not_to raise_error
    end
  end
end
