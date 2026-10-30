require "rails_helper"

RSpec.describe Spirely::PcoOutboundProfileSyncJob do
  PERSON = "https://api.planningcenteronline.com/people/v2/people/p1".freeze

  let(:church) { create(:church) }
  let(:integration) { create(:spirely_church_integration, church: church, access_token: "token") }
  let(:family) do
    create(:spirely_family, church: church, primary_contact_first_name: "Ana", primary_contact_last_name: "Rivera",
                            email: "ana@example.com", phone: "555-0142")
  end

  before do
    Spirely.configuration.encryption_key = SecureRandom.hex(32)
    integration
    # Created with sync off so saving the family doesn't queue this job itself.
    family.update_columns(pco_sync_enabled: true, pco_person_id: "p1")
    create(:spirely_sync_setting, church: church, outbound_people_sync: true)
  end

  def json(body)
    { status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" } }
  end

  def stub_patch
    stub_request(:patch, PERSON).to_return(json({ "data" => { "id" => "p1" } }))
  end

  it "updates the person's name, email and phone in PCO and records when" do
    patch = stub_patch

    described_class.perform_now(family.id)

    expect(a_request(:patch, PERSON).with(body: { "data" => {
      "type" => "Person", "id" => "p1", "attributes" => {
        "first_name" => "Ana", "last_name" => "Rivera",
        "contact_data" => { "email_addresses" => [{ "address" => "ana@example.com", "primary" => true }],
                            "phone_numbers"   => [{ "number" => "555-0142", "primary" => true }] }
      }
    } })).to have_been_made.once
    expect(patch).to have_been_requested.once
    expect(family.reload.pco_last_synced_at).to be_present
  end

  it "leaves the phone out when the family has none" do
    family.update_columns(phone: nil)
    stub_patch

    described_class.perform_now(family.id)

    expect(a_request(:patch, PERSON).with { |req|
      JSON.parse(req.body).dig("data", "attributes", "contact_data", "phone_numbers") == []
    }).to have_been_made.once
  end

  it "updates the person's address when it changed" do
    family.update_columns(address: "1 Main St, Fairfax, VA 22032")
    stub_patch
    stub_request(:get, "#{PERSON}/addresses").to_return(json({ "data" => [
      { "id" => "a1", "attributes" => { "primary" => true, "street_line_1" => "9 Old Rd", "city" => "Reston",
                                        "state" => "VA", "zip" => "20190" } },
    ] }))
    address = stub_request(:patch, "#{PERSON}/addresses/a1")
      .with(body: { "data" => { "type" => "Address", "id" => "a1", "attributes" => {
        "street_line_1" => "1 Main St", "city" => "Fairfax", "state" => "VA", "zip" => "22032"
      } } })
      .to_return(json({ "data" => { "id" => "a1" } }))

    described_class.perform_now(family.id)

    expect(address).to have_been_requested.once
  end

  it "lets a PCO error through so the job is retried, without marking the family synced" do
    stub_request(:patch, PERSON).to_return(status: 422, body: { "errors" => [] }.to_json)

    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    begin
      expect { described_class.perform_now(family.id) }.to have_enqueued_job(described_class).with(family.id)
    ensure
      ActiveJob::Base.queue_adapter = original
    end
    expect(family.reload.pco_last_synced_at).to be_nil
  end

  describe "does nothing" do
    it "when the church has outbound sync turned off" do
      church.sync_setting.update!(outbound_people_sync: false)
      described_class.perform_now(family.id)
      expect(a_request(:any, /planningcenteronline/)).not_to have_been_made
    end

    it "for a family with PCO sync turned off" do
      family.update_columns(pco_sync_enabled: false)
      described_class.perform_now(family.id)
      expect(a_request(:any, /planningcenteronline/)).not_to have_been_made
    end

    it "for a family not yet in PCO" do
      family.update_columns(pco_person_id: nil)
      described_class.perform_now(family.id)
      expect(a_request(:any, /planningcenteronline/)).not_to have_been_made
    end

    it "when the church hasn't connected PCO" do
      integration.update_columns(access_token: nil)
      described_class.perform_now(family.id)
      expect(a_request(:any, /planningcenteronline/)).not_to have_been_made
    end

    it "for a family that no longer exists" do
      expect { described_class.perform_now(0) }.not_to raise_error
    end
  end
end
