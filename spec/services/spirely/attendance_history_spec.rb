require "rails_helper"

RSpec.describe Spirely::AttendanceHistory do
  include ActiveSupport::Testing::TimeHelpers
  # The gem has no churches.timezone column, so Spirely::ChurchTime uses
  # Time.zone here; Eastern, like jccag.
  around { |ex| Time.use_zone("America/New_York") { travel_to(Time.zone.parse("2026-11-10 12:00")) { ex.run } } }

  let(:church) { create(:church) }
  let(:kid)    { create(:spirely_person, church: church, first_name: "Emma") }
  let(:other)  { create(:spirely_person, church: church, first_name: "Other") }

  # One occurrence of a Check-Ins service time (its own PCO EventTime).
  def service(starts_at, wday:, hour:, minute: 0, event: "JCC Kidz", name: nil)
    { id: "et-#{SecureRandom.hex(4)}", starts_at: Time.find_zone("UTC").parse(starts_at), event: event,
      wday: wday, hour: hour, minute: minute, name: name }
  end

  def check_in(person, svc, kind: "regular")
    create(:spirely_attendance, person: person, event_name: svc[:event], checked_in_at: svc[:starts_at] - 10.minutes,
           kind: kind, pco_event_time_id: svc[:id], event_time_starts_at: svc[:starts_at], event_time_name: svc[:name],
           event_time_day_of_week: svc[:wday], event_time_hour: svc[:hour], event_time_minute: svc[:minute])
  end

  def sundays(hour_utc, n, wday: 0, hour:)
    (1..n).map { |w| service((Time.find_zone("UTC").parse("2026-11-08 #{hour_utc}:00") - (n - w).weeks).iso8601, wday: wday, hour: hour) }
  end

  def rows = described_class.new(church, kid).rows

  it "gives each service time the kid has been to its own row, with the last 10 occurrences" do
    morning = sundays(16, 12, hour: 11)
    evening = sundays(23, 3, hour: 18)
    (morning + evening).each { |s| check_in(other, s) }
    morning.each_with_index { |s, i| check_in(kid, s) unless [3, 10].include?(i) }
    check_in(kid, evening[1])

    expect(rows.map(&:title)).to eq(["JCC Kidz · Sunday 11:00 AM", "JCC Kidz · Sunday 6:00 PM"])
    am = rows.first
    expect(am.kind).to eq("check_in")
    expect(am.meetings.size).to eq(10)
    # Missed the 4th and 11th of 12: the last 10 start at the 3rd.
    expect(am.meetings.map { |m| m[:attended] }).to eq([true, false, true, true, true, true, true, true, false, true])
    expect(am.meetings.last[:date]).to eq("2026-11-08")
    expect(rows.second.meetings.map { |m| m[:attended] }).to eq([false, true, false])
  end

  describe "an early check-in time" do
    # jccag's check-in window opens early (9:00, 10:10, during Sunday
    # School) for the 11:00 service. Sunday School's own attendance is the group roll.
    def week(n, hour_utc, minute, hour:, name: nil)
      at = Time.find_zone("UTC").parse("2026-11-08 #{hour_utc}:#{format('%02d', minute)}") - (3 - n).weeks
      service(at.iso8601, wday: 0, hour: hour, minute: minute, name: name)
    end

    let(:early)   { (1..3).map { |n| week(n, 15, 10, hour: 10) } }
    let(:service_) { (1..3).map { |n| week(n, 16, 0, hour: 11) } }

    before { (early + service_).each { |s| check_in(other, s) } }

    it "counts toward the service that starts less than 90 minutes later, with no row of its own" do
      check_in(kid, early[0])
      check_in(kid, service_[1])

      expect(rows.map(&:title)).to eq(["JCC Kidz · Sunday 11:00 AM"])
      expect(rows.sole.meetings).to eq([
        { date: "2026-10-25", attended: true }, { date: "2026-11-01", attended: true }, { date: "2026-11-08", attended: false },
      ])
    end

    it "gives a kid who only checks in early the later service's row" do
      check_in(kid, early[2])
      expect(rows.sole.title).to eq("JCC Kidz · Sunday 11:00 AM")
      expect(rows.sole.meetings.map { |m| m[:attended] }).to eq([false, false, true])
    end

    it "uses the later service's PCO name" do
      named = week(3, 16, 0, hour: 11, name: "JCC Kidz Service")
      check_in(other, named)
      check_in(kid, early[2])
      expect(rows.sole.title).to eq("JCC Kidz · JCC Kidz Service")
    end

    it "chains: a 9:00 check-in counts toward 11:00 through 10:10" do
      nine = week(3, 14, 0, hour: 9)
      check_in(kid, nine)
      check_in(kid, early[1])
      expect(rows.map(&:title)).to eq(["JCC Kidz · Sunday 11:00 AM"])
      expect(rows.sole.meetings.map { |m| m[:attended] }).to eq([false, true, true])
    end

    it "keeps a time 90 minutes or more before the next one as its own service" do
      four = service("2026-11-08T21:00:00Z", wday: 0, hour: 16)
      six  = service("2026-11-08T23:00:00Z", wday: 0, hour: 18)
      check_in(kid, four)
      check_in(kid, six)
      expect(rows.map(&:title)).to eq(["JCC Kidz · Sunday 4:00 PM", "JCC Kidz · Sunday 6:00 PM"])
    end

    it "only joins times of the same event" do
      other_event = service("2026-11-08T15:10:00Z", wday: 0, hour: 10, minute: 10, event: "Nursery")
      check_in(kid, other_event)
      expect(rows.map(&:title)).to eq(["Nursery · Sunday 10:10 AM"])
    end
  end

  it "uses PCO's own name for the service time when it has one" do
    s = service("2026-11-08T16:00:00Z", wday: 0, hour: 11, name: "Second Service")
    check_in(kid, s)
    expect(rows.sole.title).to eq("JCC Kidz · Second Service")
  end

  it "leaves out services the kid has never been to, and check-ins with no service time" do
    s = service("2026-11-08T16:00:00Z", wday: 0, hour: 11)
    check_in(other, s)
    create(:spirely_attendance, person: kid, event_name: "JCC Kidz", checked_in_at: 1.week.ago) # no event time
    expect(rows).to be_empty
  end

  it "only uses the church's kids services when some are mapped" do
    church.create_sync_setting!(pco_kids_service_types: [{ "check_ins_event_name" => "JCC Kidz" }])
    check_in(kid, service("2026-11-08T16:00:00Z", wday: 0, hour: 11))
    check_in(kid, service("2026-11-07T15:00:00Z", wday: 6, hour: 10, event: "Christmas Musical"))
    expect(rows.map(&:title)).to eq(["JCC Kidz · Sunday 11:00 AM"])
  end

  describe "group rows" do
    def kids_group(name, type)
      church.groups.create!(name: name, pco_group_id: "g-#{SecureRandom.hex(4)}", group_type: type)
    end

    def member!(group, joined: 1.year.ago)
      church.group_memberships.create!(group: group, person: kid, role: "member",
                                       pco_membership_id: "m-#{SecureRandom.hex(4)}", joined_at: joined)
    end

    # Weekly meetings, `last` given as a UTC instant (default: Wednesday
    # 2026-11-04 7 PM Eastern), attendance taken for each.
    def meetings!(group, pattern, last: "2026-11-05 00:00")
      pattern.each_with_index.map do |came, i|
        e = meeting(church, group, Time.find_zone("UTC").parse(last) - (pattern.size - 1 - i).weeks)
        church.group_attendances.create!(group_event: e, person: other, attended: true)
        church.group_attendances.create!(group_event: e, person: kid, attended: came == 1) unless came.nil?
        e
      end
    end

    let(:rangers) { church.group_types.create!(name: "Royal Rangers", pco_group_type_id: "gt-1", audience: "children") }

    it "gives each group type one row, named for the type, with the kid's class" do
      g = kids_group("Adventure Rangers", rangers)
      member!(g)
      meetings!(g, [1, 1, 0, 1])

      row = rows.sole
      expect(row).to have_attributes(kind: "group", title: "Royal Rangers", subtitle: "Adventure Rangers")
      expect(row.meetings.map { |m| m[:attended] }).to eq([true, true, false, true])
      expect(row.meetings.last[:date]).to eq("2026-11-04")
    end

    it "skips meetings where no attendance was taken, and meetings before the kid joined" do
      g = kids_group("Adventure Rangers", rangers)
      member!(g, joined: Time.find_zone("UTC").parse("2026-10-20"))
      meetings!(g, [1, 1, 1, 0, 1])
      meeting(church, g, Time.find_zone("UTC").parse("2026-11-06 00:00")) # nobody took attendance
      # Meetings Oct 8, 15, 22, 29 and Nov 5 (UTC); joined Oct 20.
      expect(rows.sole.meetings.map { |m| m[:attended] }).to eq([true, false, true])
    end

    it "counts a meeting where attendance was taken but the kid wasn't marked as missed" do
      g = kids_group("Adventure Rangers", rangers)
      member!(g)
      meetings!(g, [1, nil])
      expect(rows.sole.meetings.map { |m| m[:attended] }).to eq([true, false])
    end

    it "has no row for a group that never takes attendance, or one the kid left" do
      never = kids_group("Discovery Rangers", rangers)
      member!(never)
      meeting(church, never, 1.week.ago)
      left = kids_group("Girls Only", church.group_types.create!(name: "Girls Ministries", pco_group_type_id: "gt-2"))
      member!(left).update!(left_at: 1.month.ago)
      meetings!(left, [1, 1])
      expect(rows).to be_empty
    end

    it "orders every row through the week, groups and services together" do
      ss = kids_group("Primary", church.group_types.create!(name: "Sunday School", pco_group_type_id: "gt-3"))
      member!(ss)
      meetings!(ss, [1], last: "2026-11-08 15:10") # Sunday 10:10 AM Eastern (UTC instant)
      rr = kids_group("Adventure Rangers", rangers)
      member!(rr)
      meetings!(rr, [1]) # Wednesday 7 PM Eastern
      check_in(kid, service("2026-11-08T16:00:00Z", wday: 0, hour: 11))

      expect(rows.map(&:title)).to eq(["Sunday School", "JCC Kidz · Sunday 11:00 AM", "Royal Rangers"])
    end
  end
end
