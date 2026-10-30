require "rails_helper"

RSpec.describe Spirely::PcoAttendanceSyncJob do
  before { Spirely.configuration.encryption_key = SecureRandom.hex(32) }

  let(:church) { create(:church) }

  def stub_check_ins(data:, included:)
    stub_request(:get, "https://api.planningcenteronline.com/check-ins/v2/check_ins")
      .with(query: hash_including("per_page" => "100"))
      .to_return(status: 200, body: { data: data, included: included, links: {} }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  def stub_events(event_id:, name:)
    stub_request(:get, "https://api.planningcenteronline.com/check-ins/v2/events")
      .with(query: hash_including("where" => hash_including("id" => event_id)))
      .to_return(status: 200, body: {
        data: [{ id: event_id, type: "Event", attributes: { name: name } }],
      }.to_json, headers: { "Content-Type" => "application/json" })
  end

  def stub_locations(locations = [])
    stub_request(:get, "https://api.planningcenteronline.com/check-ins/v2/locations")
      .with(query: hash_including("per_page" => "100"))
      .to_return(status: 200, body: { data: locations, links: {} }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  let!(:integration) do
    create(:spirely_church_integration, church: church, access_token: "tok",
                                         pco_client_id: "id", pco_client_secret: "sec")
  end

  # Locations are fetched unconditionally on every sync (see
  # PcoAttendanceSyncJob#resolve_locations) — most examples below don't
  # care about them, so stub an empty list by default.
  before { stub_locations }

  it "does nothing when the church has no connected PCO integration" do
    integration.update!(access_token: nil)

    described_class.new.perform(church.id)

    expect(WebMock).not_to have_requested(:get, /planningcenteronline/)
  end

  it "creates a Person and Attendance from a real-shaped PCO check-ins response" do
    check_in = {
      id: "checkin-1", type: "CheckIn",
      attributes: { created_at: "2026-08-01T14:03:00Z", kind: "regular", one_time_guest: false },
      relationships: {
        person: { data: { id: "person-1", type: "Person" } },
        event_period: { data: { id: "period-1", type: "EventPeriod" } },
      },
    }
    person = { id: "person-1", type: "Person",
               attributes: { first_name: "Suzy", last_name: "Q", child: true, birthdate: "2018-04-01" } }
    event_period = { id: "period-1", type: "EventPeriod",
                      relationships: { event: { data: { id: "event-1", type: "Event" } } } }

    stub_check_ins(data: [check_in], included: [person, event_period])
    stub_events(event_id: "event-1", name: "Sunday 9am")

    described_class.new.perform(church.id)

    created_person = church.people.find_by(pco_person_id: "person-1")
    expect(created_person).to have_attributes(first_name: "Suzy", last_name: "Q", child: true)

    attendance = church.attendances.find_by(pco_check_in_id: "checkin-1")
    expect(attendance).to have_attributes(
      person_id: created_person.id,
      pco_event_id: "event-1",
      event_name: "Sunday 9am",
      kind: "regular",
      one_time_guest: false
    )
    expect(attendance.checked_in_at).to eq(Time.zone.parse("2026-08-01T14:03:00Z"))
  end

  it "trusts a minor's birthdate over PCO's own child:false flag when they check in" do
    check_in = {
      id: "checkin-misclassified", type: "CheckIn",
      attributes: { created_at: "2026-08-01T14:03:00Z", kind: "regular", one_time_guest: false },
      relationships: {
        person: { data: { id: "person-james", type: "Person" } },
        event_period: { data: { id: "period-1", type: "EventPeriod" } },
      },
    }
    person = { id: "person-james", type: "Person",
               attributes: { first_name: "James", last_name: "Howard", child: false, birthdate: 5.years.ago.to_date.iso8601 } }
    event_period = { id: "period-1", type: "EventPeriod",
                      relationships: { event: { data: { id: "event-1", type: "Event" } } } }

    stub_check_ins(data: [check_in], included: [person, event_period])
    stub_events(event_id: "event-1", name: "Sunday 9am")

    described_class.new.perform(church.id)

    created_person = church.people.find_by(pco_person_id: "person-james")
    expect(created_person.child).to eq(true)
  end

  it "does not override PCO's child:false flag for someone with a clearly-adult birthdate" do
    check_in = {
      id: "checkin-real-adult", type: "CheckIn",
      attributes: { created_at: "2026-08-01T14:03:00Z", kind: "regular", one_time_guest: false },
      relationships: {
        person: { data: { id: "person-tom", type: "Person" } },
        event_period: { data: { id: "period-1", type: "EventPeriod" } },
      },
    }
    person = { id: "person-tom", type: "Person",
               attributes: { first_name: "Tom", last_name: "Howard", child: false, birthdate: 40.years.ago.to_date.iso8601 } }
    event_period = { id: "period-1", type: "EventPeriod",
                      relationships: { event: { data: { id: "event-1", type: "Event" } } } }

    stub_check_ins(data: [check_in], included: [person, event_period])
    stub_events(event_id: "event-1", name: "Sunday 9am")

    described_class.new.perform(church.id)

    created_person = church.people.find_by(pco_person_id: "person-tom")
    expect(created_person.child).to eq(false)
  end

  it "normalizes PCO's real Title Case kind values (\"Regular\", \"Volunteer\") to this app's lowercase enum" do
    check_in = {
      id: "checkin-titlecase", type: "CheckIn",
      attributes: { created_at: "2026-08-01T14:03:00Z", kind: "Volunteer", one_time_guest: false },
      relationships: {
        person: { data: { id: "person-1", type: "Person" } },
        event_period: { data: { id: "period-1", type: "EventPeriod" } },
      },
    }
    person = { id: "person-1", type: "Person", attributes: { first_name: "Suzy", last_name: "Q" } }
    event_period = { id: "period-1", type: "EventPeriod",
                      relationships: { event: { data: { id: "event-1", type: "Event" } } } }

    stub_check_ins(data: [check_in], included: [person, event_period])
    stub_events(event_id: "event-1", name: "Sunday 9am")

    described_class.new.perform(church.id)

    attendance = church.attendances.find_by(pco_check_in_id: "checkin-titlecase")
    expect(attendance.kind).to eq("volunteer")
  end

  it "syncs checked_out_at, medical_notes, and location from a real-shaped response" do
    check_in = {
      id: "checkin-full", type: "CheckIn",
      attributes: {
        created_at: "2026-08-01T14:03:00Z", checked_out_at: "2026-08-01T15:30:00Z",
        kind: "Regular", one_time_guest: false, medical_notes: "Peanut allergy",
      },
      relationships: {
        person: { data: { id: "person-1", type: "Person" } },
        event_period: { data: { id: "period-1", type: "EventPeriod" } },
        check_in_times: { data: [{ id: "cit-1", type: "CheckInTime" }] },
      },
    }
    check_in_time = {
      id: "cit-1", type: "CheckInTime",
      relationships: {
        check_in: { data: { id: "checkin-full", type: "CheckIn" } },
        location: { data: { id: "loc-1", type: "Location" } },
      },
    }
    person = { id: "person-1", type: "Person", attributes: { first_name: "Suzy", last_name: "Q" } }
    event_period = { id: "period-1", type: "EventPeriod",
                      relationships: { event: { data: { id: "event-1", type: "Event" } } } }

    stub_check_ins(data: [check_in], included: [person, event_period, check_in_time])
    stub_events(event_id: "event-1", name: "Sunday 9am")
    stub_locations([{ id: "loc-1", type: "Location", attributes: { name: "Nursery" } }])

    described_class.new.perform(church.id)

    attendance = church.attendances.find_by(pco_check_in_id: "checkin-full")
    expect(attendance).to have_attributes(
      medical_notes: "Peanut allergy",
      pco_location_id: "loc-1",
      location_name: "Nursery"
    )
    expect(attendance.checked_out_at).to eq(Time.zone.parse("2026-08-01T15:30:00Z"))
  end

  it "updates an already-synced attendance on re-sync (e.g. checked_out_at set after the fact)" do
    check_in_data = {
      id: "checkin-1", type: "CheckIn",
      attributes: { created_at: "2026-08-01T14:03:00Z", checked_out_at: nil, kind: "regular", one_time_guest: false },
      relationships: {
        person: { data: { id: "person-1", type: "Person" } },
        event_period: { data: { id: "period-1", type: "EventPeriod" } },
      },
    }
    person = { id: "person-1", type: "Person", attributes: { first_name: "Suzy", last_name: "Q" } }
    event_period = { id: "period-1", type: "EventPeriod",
                      relationships: { event: { data: { id: "event-1", type: "Event" } } } }

    stub_check_ins(data: [check_in_data], included: [person, event_period])
    stub_events(event_id: "event-1", name: "Sunday 9am")
    described_class.new.perform(church.id)

    expect(church.attendances.find_by(pco_check_in_id: "checkin-1").checked_out_at).to be_nil

    checked_out = check_in_data.deep_merge(attributes: { checked_out_at: "2026-08-01T15:00:00Z" })
    stub_check_ins(data: [checked_out], included: [person, event_period])
    described_class.new.perform(church.id)

    attendance = church.attendances.find_by(pco_check_in_id: "checkin-1")
    expect(attendance.checked_out_at).to eq(Time.zone.parse("2026-08-01T15:00:00Z"))
    expect(church.attendances.where(pco_check_in_id: "checkin-1").count).to eq(1)
  end

  it "is idempotent - re-running does not create duplicate attendances" do
    check_in = {
      id: "checkin-1", type: "CheckIn",
      attributes: { created_at: "2026-08-01T14:03:00Z", kind: "regular", one_time_guest: false },
      relationships: {
        person: { data: { id: "person-1", type: "Person" } },
        event_period: { data: { id: "period-1", type: "EventPeriod" } },
      },
    }
    person = { id: "person-1", type: "Person", attributes: { first_name: "Suzy", last_name: "Q" } }
    event_period = { id: "period-1", type: "EventPeriod",
                      relationships: { event: { data: { id: "event-1", type: "Event" } } } }

    stub_check_ins(data: [check_in], included: [person, event_period])
    stub_events(event_id: "event-1", name: "Sunday 9am")

    described_class.new.perform(church.id)
    described_class.new.perform(church.id)

    expect(church.attendances.where(pco_check_in_id: "checkin-1").count).to eq(1)
  end

  it "skips a check-in with no linked person without blowing up the whole sync" do
    check_in_no_person = {
      id: "checkin-orphan", type: "CheckIn",
      attributes: { created_at: "2026-08-01T14:03:00Z", kind: "regular", one_time_guest: false },
      relationships: {
        person: { data: nil },
        event_period: { data: { id: "period-1", type: "EventPeriod" } },
      },
    }
    event_period = { id: "period-1", type: "EventPeriod",
                      relationships: { event: { data: { id: "event-1", type: "Event" } } } }

    stub_check_ins(data: [check_in_no_person], included: [event_period])
    stub_events(event_id: "event-1", name: "Sunday 9am")

    expect { described_class.new.perform(church.id) }.not_to raise_error
    expect(church.attendances.count).to eq(0)
  end

  it "raises Spirely::PcoError when PCO returns a non-2xx response" do
    stub_request(:get, "https://api.planningcenteronline.com/check-ins/v2/check_ins")
      .with(query: hash_including("per_page" => "100"))
      .to_return(status: 500, body: "boom")

    expect { described_class.new.perform(church.id) }.to raise_error(Spirely::PcoError)
  end

  it "reads 26 weeks back on a church's first sync, then the usual 16 weeks" do
    stub_check_ins(data: [], included: [])
    now = Time.zone.parse("2026-10-22 12:00")
    gte = ->(window) { (now - window).iso8601 }

    travel_to(now) { described_class.perform_now(church.id) }
    expect(a_request(:get, %r{check-ins/v2/check_ins}).with(query: hash_including("where" => { "created_at" => { "gte" => gte.(26.weeks) } })))
      .to have_been_made
    expect(church.sync_setting.reload.checkins_history_synced_at).to be_present

    travel_to(now) { described_class.perform_now(church.id) }
    expect(a_request(:get, %r{check-ins/v2/check_ins}).with(query: hash_including("where" => { "created_at" => { "gte" => gte.(16.weeks) } })))
      .to have_been_made
  end
end
