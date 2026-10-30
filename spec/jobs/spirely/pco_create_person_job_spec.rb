require "rails_helper"

RSpec.describe Spirely::PcoCreatePersonJob do
  include ActiveJob::TestHelper

  PEOPLE = "https://api.planningcenteronline.com/people/v2".freeze

  let(:church) { create(:church) }
  let(:integration) { create(:spirely_church_integration, church: church, access_token: "token") }
  let(:family) do
    create(:spirely_family, church: church, family_name: "Rivera", primary_contact_first_name: "Ana",
                            primary_contact_last_name: "Rivera", email: "ana@example.com", phone: "555-0142",
                            pco_sync_enabled: true)
  end

  before do
    Spirely.configuration.encryption_key = SecureRandom.hex(32)
    integration
  end

  # The app's adapter is :async outside production; retries need :test.
  around do |example|
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = original
  end

  def json(body, status: 200)
    { status: status, body: body.to_json, headers: { "Content-Type" => "application/json" } }
  end

  def stub_person_create(id: "p1", created_at: "2026-10-01T15:00:00Z")
    stub_request(:post, "#{PEOPLE}/people")
      .with(body: hash_including("data" => hash_including("attributes" => hash_including("first_name" => "Ana"))))
      .to_return(json({ "data" => { "id" => id, "attributes" => { "created_at" => created_at } } }))
  end

  def stub_contact(person_id = "p1")
    stub_request(:post, "#{PEOPLE}/people/#{person_id}/emails").to_return(json({ "data" => { "id" => "e1" } }))
    stub_request(:post, "#{PEOPLE}/people/#{person_id}/phone_numbers").to_return(json({ "data" => { "id" => "ph1" } }))
  end

  it "creates the person with their email and phone, and records the PCO id and creation time" do
    person = stub_person_create
    stub_contact

    described_class.perform_now(family.id)

    expect(person).to have_been_requested.once
    expect(a_request(:post, "#{PEOPLE}/people/p1/emails").with(body: {
      "data" => { "type" => "Email", "attributes" => { "address" => "ana@example.com", "primary" => true, "location" => "Home" } }
    })).to have_been_made
    expect(a_request(:post, "#{PEOPLE}/people/p1/phone_numbers").with(body: {
      "data" => { "type" => "PhoneNumber", "attributes" => { "number" => "555-0142", "primary" => true, "location" => "Mobile" } }
    })).to have_been_made

    family.reload
    expect(family.pco_person_id).to eq("p1")
    expect(family.pco_created_at).to eq(Time.zone.parse("2026-10-01T15:00:00Z"))
    expect(family.pco_last_synced_at).to be_present
  end

  it "skips email and phone the family doesn't have" do
    family.update_columns(email: nil, phone: nil)
    stub_person_create

    described_class.perform_now(family.id)

    expect(a_request(:post, %r{/emails})).not_to have_been_made
    expect(a_request(:post, %r{/phone_numbers})).not_to have_been_made
    expect(family.reload.pco_last_synced_at).to be_present
  end

  it "creates the children and links them to the parent through a new household" do
    family.update_columns(phone: nil)
    kid = create(:spirely_child, family: family, first_name: "Leo", last_name: "Rivera", grade: 2,
                                 birthdate: Date.new(2018, 4, 9), notes: "Peanut allergy")
    stub_person_create
    stub_contact
    child = stub_request(:post, "#{PEOPLE}/people")
      .with(body: { "data" => { "type" => "Person", "attributes" => {
        "first_name" => "Leo", "last_name" => "Rivera", "child" => true, "grade" => 2,
        "birthdate" => "2018-04-09", "medical_notes" => "Peanut allergy"
      } } })
      .to_return(json({ "data" => { "id" => "c1" } }))
    household = stub_request(:post, "#{PEOPLE}/households")
      .with(body: { "data" => { "type" => "Household", "attributes" => { "name" => "Rivera", "primary_contact_id" => "p1" } } })
      .to_return(json({ "data" => { "id" => "h1" } }))
    membership = stub_request(:post, "#{PEOPLE}/households/h1/household_memberships")
      .with(body: { "data" => { "type" => "HouseholdMembership",
                                "attributes" => { "person_id" => "c1", "household_role" => "child_or_dependent" } } })
      .to_return(json({ "data" => { "id" => "hm1" } }))

    described_class.perform_now(family.id)

    expect(child).to have_been_requested.once
    expect(household).to have_been_requested.once
    expect(membership).to have_been_requested.once
    expect(kid.reload.pco_person_id).to eq("c1")
    expect(family.reload.pco_household_id).to eq("h1")
  end

  it "makes no household when there are no children" do
    stub_person_create
    stub_contact

    described_class.perform_now(family.id)

    expect(a_request(:post, "#{PEOPLE}/households")).not_to have_been_made
  end

  # 2026-08-07: retries after a later step failed each created another
  # person, leaving 10 copies of one parent in jccag's PCO.
  describe "retrying after a step failed partway" do
    it "keeps the person it already created and finishes the rest" do
      stub_person_create
      stub_request(:post, "#{PEOPLE}/people/p1/emails")
        .to_return(json({ "errors" => [] }, status: 500)).then
        .to_return(json({ "data" => { "id" => "e1" } }))
      stub_request(:post, "#{PEOPLE}/people/p1/phone_numbers").to_return(json({ "data" => { "id" => "ph1" } }))

      # ApplicationJob's retry_on schedules the next attempt.
      expect { described_class.perform_now(family.id) }.to have_enqueued_job(described_class).with(family.id)
      expect(family.reload.pco_person_id).to eq("p1")
      expect(family.pco_last_synced_at).to be_nil

      perform_enqueued_jobs

      expect(a_request(:post, "#{PEOPLE}/people")).to have_been_made.once
      expect(family.reload.pco_last_synced_at).to be_present
    end

    it "doesn't recreate children or a household that already exist" do
      family.update_columns(pco_person_id: "p1", pco_household_id: "h1", phone: nil)
      create(:spirely_child, family: family, pco_person_id: "c1")
      stub_contact
      membership = stub_request(:post, "#{PEOPLE}/households/h1/household_memberships")
        .to_return(json({ "data" => { "id" => "hm1" } }))

      described_class.perform_now(family.id)

      expect(a_request(:post, "#{PEOPLE}/people")).not_to have_been_made
      expect(a_request(:post, "#{PEOPLE}/households")).not_to have_been_made
      expect(membership).to have_been_requested.once
    end
  end

  it "tags the person with the church's ministry tag" do
    create(:spirely_sync_setting, church: church, pco_ministry_tag: "Kids Ministry")
    stub_person_create
    stub_contact
    stub_request(:get, "#{PEOPLE}/tags").with(query: hash_including("where" => { "name" => "Kids Ministry" }))
      .to_return(json({ "data" => [{ "id" => "t9", "attributes" => { "name" => "Kids Ministry" } }] }))
    tagging = stub_request(:post, "#{PEOPLE}/tags/t9/relationships/people")
      .with(body: { "data" => [{ "type" => "Person", "id" => "p1" }] })
      .to_return(json({ "data" => [] }))

    described_class.perform_now(family.id)

    expect(tagging).to have_been_requested.once
  end

  it "skips tagging when PCO has no tag by that name" do
    create(:spirely_sync_setting, church: church, pco_ministry_tag: "Kids Ministry")
    stub_person_create
    stub_contact
    stub_request(:get, "#{PEOPLE}/tags").with(query: hash_including({}))
      .to_return(json({ "data" => [{ "id" => "t2", "attributes" => { "name" => "Kids Ministry Volunteers" } }] }))

    described_class.perform_now(family.id)

    expect(a_request(:post, %r{/tags/.*/relationships/people})).not_to have_been_made
    expect(family.reload.pco_last_synced_at).to be_present
  end

  it "adds the family's address as the person's primary Home address" do
    family.update_columns(address: "10718 John Turley Pl, Fairfax, VA, 22032")
    stub_person_create
    stub_contact
    stub_request(:get, "#{PEOPLE}/people/p1/addresses").to_return(json({ "data" => [] }))
    address = stub_request(:post, "#{PEOPLE}/people/p1/addresses")
      .with(body: { "data" => { "type" => "Address", "attributes" => {
        "street_line_1" => "10718 John Turley Pl", "city" => "Fairfax", "state" => "VA", "zip" => "22032",
        "location" => "Home", "primary" => true
      } } })
      .to_return(json({ "data" => { "id" => "a1" } }))

    described_class.perform_now(family.id)

    expect(address).to have_been_requested.once
  end

  describe "does nothing" do
    it "for a family that has already finished syncing" do
      family.update_columns(pco_last_synced_at: 1.day.ago)
      described_class.perform_now(family.id)
      expect(a_request(:any, /planningcenteronline/)).not_to have_been_made
    end

    it "for a family with PCO sync turned off" do
      family.update_columns(pco_sync_enabled: false)
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
