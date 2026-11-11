require "rails_helper"

RSpec.describe Spirely::CheckInServices do
  include ActiveSupport::Testing::TimeHelpers
  around { |ex| Time.use_zone("America/New_York") { travel_to(Time.zone.parse("2026-11-10 12:00")) { ex.run } } }

  let(:church) { create(:church) }
  let(:kid)    { create(:spirely_person, church: church) }
  let(:other)  { create(:spirely_person, church: church) }

  def service(at, wday: 0, hour:, minute: 0, event: "JCC Kidz", opens: 30)
    at = Time.find_zone("UTC").parse(at)
    { id: "et-#{SecureRandom.hex(4)}", starts_at: at, shows_at: at - opens.minutes, event: event, wday: wday, hour: hour, minute: minute }
  end

  def check_in(person, svc, kind: "regular", one_time_guest: false)
    create(:spirely_attendance, person: person, event_name: svc[:event], checked_in_at: svc[:starts_at] - 10.minutes,
           kind: kind, one_time_guest: one_time_guest, pco_event_time_id: svc[:id], event_time_starts_at: svc[:starts_at],
           event_time_shows_at: svc[:shows_at], event_time_day_of_week: svc[:wday], event_time_hour: svc[:hour],
           event_time_minute: svc[:minute])
  end

  let(:mornings) { %w[2026-10-25 2026-11-01 2026-11-08].map { |d| service("#{d}T16:00:00Z", hour: 11) } }
  let(:evenings) { %w[2026-10-25 2026-11-01 2026-11-08].map { |d| service("#{d}T23:00:00Z", hour: 18) } }

  it "lists each service time with every date it happened and who came" do
    (mornings + evenings).each { |s| check_in(other, s) }
    check_in(kid, evenings[0])
    check_in(kid, evenings[2])

    services = described_class.new(church).all
    expect(services.map(&:title)).to eq(["JCC Kidz · Sunday 11:00 AM", "JCC Kidz · Sunday 6:00 PM"])
    evening = services.second
    expect(evening.key).to eq("JCC Kidz|0|18|0")
    expect(evening.dates).to eq(%w[2026-10-25 2026-11-01 2026-11-08])
    expect(evening.attended_dates(kid.id)).to eq(Set["2026-10-25", "2026-11-08"])
    expect(evening.attended_dates(create(:spirely_person, church: church).id)).to be_empty
  end

  it "lists only the services a person has come to with for_person" do
    (mornings + evenings).each { |s| check_in(other, s) }
    check_in(kid, evenings[1])
    expect(described_class.new(church).for_person(kid.id).map(&:key)).to eq(["JCC Kidz|0|18|0"])
  end

  it "counts an early check-in toward the later service whose window it starts in" do
    %w[2026-11-01 2026-11-08].each { |d| check_in(other, service("#{d}T16:00:00Z", hour: 11, opens: 150)) }
    check_in(kid, service("2026-11-01T15:10:00Z", hour: 10, minute: 10))

    services = described_class.new(church).all
    expect(services.map(&:key)).to eq(["JCC Kidz|0|11|0"])
    expect(services.sole.attended_dates(kid.id)).to eq(Set["2026-11-01"])
  end

  it "leaves guest check-ins out of dates and attendance when countable_only" do
    check_in(other, mornings[0])
    check_in(kid, mornings[1], kind: "guest")
    check_in(kid, mornings[2], one_time_guest: true)

    expect(described_class.new(church).all.sole.dates.size).to eq(3)
    expect(described_class.new(church, countable_only: true).all).to be_empty # one date left: a one-off
    check_in(other, mornings[1])
    counted = described_class.new(church, countable_only: true).all.sole
    expect(counted.dates).to eq(%w[2026-10-25 2026-11-01])
    expect(counted.attended_dates(kid.id)).to be_empty
  end

  it "only uses the church's kids services when some are mapped" do
    church.create_sync_setting!(pco_kids_service_types: [{ "check_ins_event_name" => "JCC Kidz" }])
    mornings.each { |s| check_in(other, s) }
    mornings.each { |s| check_in(other, s.merge(id: "x-#{s[:id]}", event: "VBS")) }
    expect(described_class.new(church).all.map(&:event_name)).to eq(["JCC Kidz"])
  end
end
