require "rails_helper"

RSpec.describe Spirely::PcoInboundPeopleSyncJob do
  before { Spirely.configuration.encryption_key = SecureRandom.hex(32) }

  let(:church) { create(:church) }
  let!(:integration) do
    create(:spirely_church_integration, church: church, access_token: "tok",
                                         pco_client_id: "id", pco_client_secret: "sec")
  end
  let!(:sync_setting) { create(:spirely_sync_setting, church: church, inbound_people_sync: true) }

  def person(id:, first_name:, last_name:, household_id: nil, child: false, created_at: "2026-08-01T00:00:00Z",
             birthdate: nil)
    {
      "id" => id, "type" => "Person",
      "attributes" => { "first_name" => first_name, "last_name" => last_name, "child" => child,
                         "created_at" => created_at, "updated_at" => created_at, "birthdate" => birthdate, "grade" => nil,
                         "medical_notes" => nil },
      "relationships" => { "households" => { "data" => (household_id ? [{ "id" => household_id, "type" => "Household" }] : []) } },
    }
  end

  def household(id:, name:, primary_contact_id: nil)
    { "id" => id, "type" => "Household",
      "attributes" => { "name" => name, "primary_contact_id" => primary_contact_id } }
  end

  def stub_people(data:, included: [])
    stub_request(:get, "https://api.planningcenteronline.com/people/v2/people")
      .with(query: hash_including("per_page" => "100"))
      .to_return(status: 200, body: { data: data, included: included, links: {} }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  def run = described_class.new.perform(church.id)

  it "does nothing when inbound_people_sync is disabled" do
    sync_setting.update!(inbound_people_sync: false)

    run

    expect(WebMock).not_to have_requested(:get, /planningcenteronline/)
  end

  it "does nothing when PCO isn't connected" do
    integration.update!(access_token: nil)

    run

    expect(WebMock).not_to have_requested(:get, /planningcenteronline/)
  end

  it "creates a Family for a single-adult household" do
    hh = household(id: "hh-1", name: "Smith Household")
    adult = person(id: "p-1", first_name: "Jane", last_name: "Smith", household_id: "hh-1")
    stub_people(data: [adult], included: [hh])

    run

    family = church.families.find_by(pco_person_id: "p-1")
    expect(family).to have_attributes(
      family_name: "Smith Household", primary_contact_first_name: "Jane",
      pco_household_id: "hh-1"
    )
    expect(family.pco_created_at).to eq(Time.zone.parse("2026-08-01T00:00:00Z"))
    expect(family.guardians).to be_empty
  end

  it "keeps the street from PCO's street_line_1/street_line_2 address fields" do
    hh = household(id: "hh-1", name: "Bigirwa Household")
    adult = person(id: "p-1", first_name: "Afua", last_name: "Bigirwa", household_id: "hh-1")
    address = { "id" => "a-1", "type" => "Address",
                "attributes" => { "street_line_1" => "10718 John Turley Pl", "street_line_2" => nil,
                                  "city" => "Fairfax", "state" => "VA", "zip" => "22032-3120", "primary" => true },
                "relationships" => { "person" => { "data" => { "type" => "Person", "id" => "p-1" } } } }
    stub_people(data: [adult], included: [hh, address])

    run

    expect(church.families.find_by(pco_person_id: "p-1").address)
      .to eq("10718 John Turley Pl, Fairfax, VA 22032-3120")
  end

  it "decodes HTML-escaped names from PCO" do
    hh = household(id: "hh-1", name: "Bigirwa &amp; Co Household")
    adult = person(id: "p-1", first_name: "Bigz &amp; Afua", last_name: "Bigirwa", household_id: "hh-1")
    stub_people(data: [adult], included: [hh])

    run

    expect(church.families.find_by(pco_person_id: "p-1")).to have_attributes(
      primary_contact_first_name: "Bigz & Afua", family_name: "Bigirwa & Co Household"
    )
  end

  it "syncs a second adult in the same household as a Guardian, not a duplicate Family" do
    hh = household(id: "hh-1", name: "Cornett Household", primary_contact_id: "p-1")
    adult1 = person(id: "p-1", first_name: "Natalia", last_name: "Cornett", household_id: "hh-1")
    adult2 = person(id: "p-2", first_name: "Michael", last_name: "Cornett", household_id: "hh-1")
    stub_people(data: [adult1, adult2], included: [hh])

    run

    expect(church.families.where(pco_household_id: "hh-1").count).to eq(1)
    family = church.families.find_by(pco_household_id: "hh-1")
    expect(family.pco_person_id).to eq("p-1")
    expect(family.guardians.count).to eq(1)
    expect(family.guardians.first).to have_attributes(first_name: "Michael", last_name: "Cornett", pco_person_id: "p-2")
  end

  it "does not duplicate the Guardian on a second sync run" do
    hh = household(id: "hh-1", name: "Cornett Household")
    adult1 = person(id: "p-1", first_name: "Natalia", last_name: "Cornett", household_id: "hh-1")
    adult2 = person(id: "p-2", first_name: "Michael", last_name: "Cornett", household_id: "hh-1")
    stub_people(data: [adult1, adult2], included: [hh])

    run
    run

    family = church.families.find_by(pco_household_id: "hh-1")
    expect(family.guardians.count).to eq(1)
  end

  it "keeps the same adult as the Family's primary contact across repeated syncs, even if PCO's order flips" do
    hh = household(id: "hh-1", name: "Cornett Household")
    adult1 = person(id: "p-1", first_name: "Natalia", last_name: "Cornett", household_id: "hh-1")
    adult2 = person(id: "p-2", first_name: "Michael", last_name: "Cornett", household_id: "hh-1")
    stub_people(data: [adult1, adult2], included: [hh])
    run

    # Second sync returns the same two people in reverse order.
    stub_people(data: [adult2, adult1], included: [hh])
    run

    family = church.families.find_by(pco_household_id: "hh-1")
    expect(family.pco_person_id).to eq("p-1")
    expect(family.guardians.pluck(:pco_person_id)).to eq(["p-2"])
  end

  it "does not group unrelated adults with no household together" do
    solo1 = person(id: "p-1", first_name: "Alice", last_name: "Solo", household_id: nil)
    solo2 = person(id: "p-2", first_name: "Bob", last_name: "Solo", household_id: nil)
    stub_people(data: [solo1, solo2], included: [])

    run

    families = church.families.where(pco_person_id: %w[p-1 p-2])
    expect(families.count).to eq(2)
    expect(families.flat_map(&:guardians)).to be_empty
  end

  it "attaches a child to the correct family via pco_household_id" do
    hh = household(id: "hh-1", name: "Cornett Household")
    adult = person(id: "p-1", first_name: "Natalia", last_name: "Cornett", household_id: "hh-1")
    kid   = person(id: "p-3", first_name: "Nico", last_name: "Cornett", household_id: "hh-1", child: true)
    stub_people(data: [adult, kid], included: [hh])

    run

    family = church.families.find_by(pco_household_id: "hh-1")
    expect(family.children.count).to eq(1)
    expect(family.children.first).to have_attributes(first_name: "Nico", pco_person_id: "p-3")
  end

  it "does not treat a PCO household primary_contact_id pointing at a miscategorized child as the adult primary" do
    hh = household(id: "hh-1", name: "Cornett Household", primary_contact_id: "p-3") # p-3 is a child, not in the adults batch
    adult = person(id: "p-1", first_name: "Natalia", last_name: "Cornett", household_id: "hh-1")
    stub_people(data: [adult], included: [hh])

    run

    family = church.families.find_by(pco_household_id: "hh-1")
    expect(family.pco_person_id).to eq("p-1")
  end

  describe "PCO's own child/adult classification is wrong" do
    it "treats a PCO-misclassified adult as a child, given real local check-in evidence and a minor's birthdate" do
      hh = household(id: "hh-1", name: "Howard Household")
      adult = person(id: "p-1", first_name: "Sarah", last_name: "Howard", household_id: "hh-1")
      misclassified = person(id: "p-2", first_name: "James", last_name: "Howard", household_id: "hh-1",
                              child: false, birthdate: 5.years.ago.to_date.iso8601)
      stub_people(data: [adult, misclassified], included: [hh])

      checked_in_person = create(:spirely_person, church: church, pco_person_id: "p-2", child: false)
      create(:spirely_attendance, person: checked_in_person, checked_in_at: 1.day.ago)

      run

      family = church.families.find_by(pco_household_id: "hh-1")
      expect(family.children.pluck(:pco_person_id)).to eq(["p-2"])
      expect(family.guardians).to be_empty
    end

    it "does not override PCO's adult classification without local check-in evidence" do
      hh = household(id: "hh-1", name: "Howard Household")
      adult = person(id: "p-1", first_name: "Sarah", last_name: "Howard", household_id: "hh-1")
      misclassified = person(id: "p-2", first_name: "James", last_name: "Howard", household_id: "hh-1",
                              child: false, birthdate: 5.years.ago.to_date.iso8601)
      stub_people(data: [adult, misclassified], included: [hh])

      run

      family = church.families.find_by(pco_household_id: "hh-1")
      expect(family.guardians.pluck(:pco_person_id)).to eq(["p-2"])
      expect(family.children).to be_empty
    end

    it "does not override PCO's adult classification for someone with real check-in history but a clearly-adult birthdate" do
      hh = household(id: "hh-1", name: "Howard Household")
      adult = person(id: "p-1", first_name: "Sarah", last_name: "Howard", household_id: "hh-1")
      real_adult = person(id: "p-2", first_name: "Tom", last_name: "Howard", household_id: "hh-1",
                           child: false, birthdate: 40.years.ago.to_date.iso8601)
      stub_people(data: [adult, real_adult], included: [hh])

      checked_in_person = create(:spirely_person, church: church, pco_person_id: "p-2", child: false)
      create(:spirely_attendance, person: checked_in_person, checked_in_at: 1.day.ago)

      run

      family = church.families.find_by(pco_household_id: "hh-1")
      expect(family.guardians.pluck(:pco_person_id)).to eq(["p-2"])
      expect(family.children).to be_empty
    end
  end

  def contact(type, id, person_id, attrs)
    { "id" => id, "type" => type, "attributes" => attrs,
      "relationships" => { "person" => { "data" => { "id" => person_id, "type" => "Person" } } } }
  end

  it "records when the church last synced" do
    stub_people(data: [])

    run

    expect(sync_setting.reload.last_synced_at).to be_within(1.minute).of(Time.current)
  end

  describe "contact details" do
    it "takes each adult's primary email and phone, or their first when none is primary" do
      hh = household(id: "hh-1", name: "Smith Household")
      jane = person(id: "p-1", first_name: "Jane", last_name: "Smith", household_id: "hh-1")
      tom  = person(id: "p-2", first_name: "Tom", last_name: "Smith", household_id: "hh-1")
      stub_people(data: [jane, tom], included: [
        hh,
        contact("Email", "e1", "p-1", "address" => "old@example.com", "primary" => false),
        contact("Email", "e2", "p-1", "address" => "jane@example.com", "primary" => true),
        contact("PhoneNumber", "ph1", "p-1", "number" => "555-0101", "primary" => true),
        contact("Email", "e3", "p-2", "address" => "tom@example.com", "primary" => false),
        contact("PhoneNumber", "ph2", "p-2", "number" => "555-0102", "primary" => false),
      ])

      run

      family = church.families.find_by(pco_person_id: "p-1")
      expect(family).to have_attributes(email: "jane@example.com", phone: "555-0101")
      expect(family.guardians.first).to have_attributes(email: "tom@example.com", phone: "555-0102")
    end
  end

  describe "with a ministry tag" do
    before { sync_setting.update!(pco_ministry_tag: "Kids Ministry") }

    def stub_tag(found:, tagged_household_ids: [])
      tags = found ? [{ "id" => "t1", "type" => "Tag", "attributes" => { "name" => "Kids Ministry" } }] : []
      stub_request(:get, "https://api.planningcenteronline.com/people/v2/tags")
        .with(query: hash_including("where" => { "name" => "Kids Ministry" }))
        .to_return(status: 200, body: { data: tags, links: {} }.to_json, headers: { "Content-Type" => "application/json" })
      tagged = tagged_household_ids.map.with_index do |hh, i|
        { "id" => "tagged-#{i}", "type" => "Person",
          "relationships" => { "households" => { "data" => [{ "id" => hh, "type" => "Household" }] } } }
      end
      stub_request(:get, "https://api.planningcenteronline.com/people/v2/tags/t1/people")
        .with(query: hash_including({}))
        .to_return(status: 200, body: { data: tagged, links: {} }.to_json, headers: { "Content-Type" => "application/json" })
    end

    it "syncs only households with someone tagged" do
      stub_tag(found: true, tagged_household_ids: ["hh-1"])
      stub_people(data: [
        person(id: "p-1", first_name: "Jane", last_name: "Smith", household_id: "hh-1"),
        person(id: "p-2", first_name: "Raj", last_name: "Patel", household_id: "hh-2"),
      ], included: [household(id: "hh-1", name: "Smith Household"), household(id: "hh-2", name: "Patel Household")])

      run

      expect(church.families.pluck(:pco_household_id)).to eq(["hh-1"])
    end

    it "stops without syncing anyone when the tag isn't in PCO" do
      stub_tag(found: false)

      run

      expect(WebMock).not_to have_requested(:get, %r{/people/v2/people})
      expect(sync_setting.reload.last_synced_at).to be_nil
    end
  end

  describe "a family already in Spirely, edited locally" do
    let!(:family) do
      create(:spirely_family, church: church, pco_person_id: "p-1", pco_household_id: "hh-1",
                              primary_contact_first_name: "Janie", primary_contact_last_name: "Smith",
                              email: "local@example.com")
    end

    def stub_pco_jane(updated_at:)
      stub_people(data: [person(id: "p-1", first_name: "Jane", last_name: "Smith", household_id: "hh-1",
                                created_at: updated_at)],
                  included: [household(id: "hh-1", name: "Smith Household"),
                             contact("Email", "e1", "p-1", "address" => "pco@example.com", "primary" => true)])
    end

    it "takes PCO's details when PCO wins" do
      stub_pco_jane(updated_at: 1.year.ago.iso8601)

      run

      expect(family.reload).to have_attributes(primary_contact_first_name: "Jane", email: "pco@example.com")
    end

    it "keeps the local details when local wins, still recording the sync" do
      sync_setting.update!(conflict_resolution: "local_wins")
      stub_pco_jane(updated_at: 1.minute.ago.iso8601)

      run

      expect(family.reload).to have_attributes(primary_contact_first_name: "Janie", email: "local@example.com")
      expect(family.pco_last_synced_at).to be_present
    end

    describe "when the newest change wins" do
      before { sync_setting.update!(conflict_resolution: "newest_wins") }

      it "takes PCO's details when PCO changed after the local edit" do
        family.update_columns(updated_at: 2.days.ago)
        stub_pco_jane(updated_at: 1.day.ago.iso8601)

        run

        expect(family.reload).to have_attributes(primary_contact_first_name: "Jane", email: "pco@example.com")
      end

      it "keeps the local details when they changed after PCO's" do
        family.update_columns(updated_at: 1.day.ago)
        stub_pco_jane(updated_at: 2.days.ago.iso8601)

        run

        expect(family.reload).to have_attributes(primary_contact_first_name: "Janie", email: "local@example.com")
        expect(family.pco_last_synced_at).to be_present
      end
    end
  end

  describe "children" do
    let(:hh) { household(id: "hh-1", name: "Cornett Household") }
    let(:adult) { person(id: "p-1", first_name: "Natalia", last_name: "Cornett", household_id: "hh-1") }

    def kid(**attrs)
      person(id: "p-3", first_name: "Nico", last_name: "Cornett", household_id: "hh-1", child: true).tap do |k|
        k["attributes"].merge!(attrs.transform_keys(&:to_s))
      end
    end

    it "brings over birthdate, grade and medical notes" do
      stub_people(data: [adult, kid(birthdate: "2018-04-09", grade: 2, medical_notes: "Peanut allergy")], included: [hh])

      run

      expect(church.children.find_by(pco_person_id: "p-3"))
        .to have_attributes(birthdate: Date.new(2018, 4, 9), grade: 2, notes: "Peanut allergy")
    end

    it "links a child added in Spirely before PCO, by name, instead of adding them twice" do
      family = create(:spirely_family, church: church, pco_person_id: "p-1", pco_household_id: "hh-1")
      local = create(:spirely_child, family: family, first_name: "Nico", last_name: "Cornett", pco_person_id: nil)
      stub_people(data: [adult, kid], included: [hh])

      run

      expect(family.children.count).to eq(1)
      expect(local.reload.pco_person_id).to eq("p-3")
    end

    it "skips a child whose household has no family in Spirely" do
      stub_people(data: [person(id: "p-9", first_name: "Ava", last_name: "Lone", household_id: "hh-9", child: true)])

      run

      expect(church.children.where(pco_person_id: "p-9")).to be_empty
    end
  end

  it "treats an unreadable birthdate as not a minor's" do
    hh = household(id: "hh-1", name: "Howard Household")
    adult = person(id: "p-1", first_name: "Sarah", last_name: "Howard", household_id: "hh-1")
    other = person(id: "p-2", first_name: "Tom", last_name: "Howard", household_id: "hh-1", birthdate: "not-a-date")
    stub_people(data: [adult, other], included: [hh])
    create(:spirely_attendance, person: create(:spirely_person, church: church, pco_person_id: "p-2"), checked_in_at: 1.day.ago)

    run

    expect(church.families.find_by(pco_household_id: "hh-1").guardians.pluck(:pco_person_id)).to eq(["p-2"])
  end

  describe "when something fails" do
    it "retries the job on a PCO error" do
      stub_request(:get, %r{/people/v2/people}).to_return(status: 503, body: "")

      expect { described_class.perform_now(church.id) }.to have_enqueued_job(described_class).with(church.id)
      expect(sync_setting.reload.last_synced_at).to be_nil
    end

    it "carries on with everyone else when one family can't be saved" do
      stub_people(data: [
        person(id: "p-1", first_name: "Jane", last_name: "Smith", household_id: "hh-1"),
        person(id: "p-2", first_name: "Raj", last_name: "Patel", household_id: "hh-2"),
      ], included: [
        household(id: "hh-1", name: "Smith Household"), household(id: "hh-2", name: "Patel Household"),
        contact("Email", "e1", "p-1", "address" => "not an email", "primary" => true),
      ])

      run

      expect(church.families.pluck(:pco_household_id)).to eq(["hh-2"])
      expect(sync_setting.reload.last_synced_at).to be_present
    end
  end
end
