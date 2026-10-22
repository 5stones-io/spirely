require "rails_helper"

# Kudos phase 2 (5ST-61): points from check-ins, group meetings and promo
# codes. Phase 3 (5ST-62): points for time served on Services plans.
RSpec.describe Spirely::Kudos do
  let(:church)  { create(:church, enabled_modules: %w[kudos smallgroups]) }
  let(:kudos)   { described_class.new(church) }
  let(:setting) { Spirely::KudosSetting.for(church) }
  let(:emma)    { create(:spirely_person, church: church, first_name: "Emma", pco_person_id: "emma", child: true) }
  let(:mark)    { create(:spirely_person, church: church, first_name: "Mark", pco_person_id: "mark") }

  before { setting.update!(earning_starts_on: 2.weeks.ago.to_date) }

  def check_in(person, at: 1.day.ago, **attrs)
    create(:spirely_attendance, church: church, person: person, checked_in_at: at, **attrs)
  end

  def balance(person) = kudos.totals(person)[:balance]

  describe "#post_earned_points!" do
    context "check-ins" do
      before { setting.update!(rates: { "checkin" => 10 }) }

      it "pays each check-in once, however many times it runs" do
        check_in(emma)
        check_in(mark)

        expect(kudos.post_earned_points!).to eq(2)
        expect(kudos.post_earned_points!).to eq(0)
        expect(balance(emma)).to eq(10)
        expect(emma.points_entries.last).to have_attributes(source: "checkin", note: "Checked in · Sunday Service")
      end

      it "only counts check-ins from the earning start date on" do
        check_in(emma, at: 3.weeks.ago)
        expect(kudos.post_earned_points!).to eq(0)
      end

      it "pays once per person per event per day" do
        check_in(emma, at: 1.day.ago.change(hour: 9))
        check_in(emma, at: 1.day.ago.change(hour: 11))
        check_in(emma, at: 1.day.ago, pco_event_id: "wednesday", event_name: "Rangers")

        kudos.post_earned_points!
        expect(balance(emma)).to eq(20)
      end

      it "uses a per-event rate, where 0 means that event doesn't earn" do
        setting.update!(rates: { "checkin" => 10, "checkin_events" => { "wednesday" => 25, "staff" => 0 } })
        check_in(emma, pco_event_id: "wednesday", event_name: "Rangers")
        check_in(mark, pco_event_id: "staff", event_name: "Staff meeting")

        kudos.post_earned_points!
        expect(balance(emma)).to eq(25)
        expect(balance(mark)).to eq(0)
      end

      it "skips one-time guests but pays regular guests" do
        guest = create(:spirely_person, church: church, first_name: "Visitor", pco_person_id: "v1")
        check_in(guest, kind: "guest")
        check_in(mark, one_time_guest: true)

        kudos.post_earned_points!
        expect(balance(guest)).to eq(10)
        expect(balance(mark)).to eq(0)
      end

      it "keeps points when Check-Ins later drops the record" do
        check_in(emma).destroy!
        expect(balance(emma)).to eq(0) # nothing posted yet, nothing to keep
        attendance = check_in(emma)
        kudos.post_earned_points!
        attendance.delete
        kudos.post_earned_points!
        expect(balance(emma)).to eq(10)
      end

      it "posts nothing when the rates are all 0 or Kudos is off" do
        check_in(emma)
        setting.update!(rates: {})
        expect(kudos.post_earned_points!).to eq(0)

        setting.update!(rates: { "checkin" => 10 })
        church.update!(enabled_modules: ["smallgroups"])
        expect(kudos.post_earned_points!).to eq(0)
      end
    end

    context "group meetings" do
      let(:group) { church.groups.create!(name: "Rangers", pco_group_id: "g1") }

      def meeting(at: 3.days.ago, **attrs)
        church.group_events.create!(group: group, pco_event_id: "e-#{SecureRandom.hex(4)}", starts_at: at, **attrs)
      end

      def attend(event, person, attended: true)
        event.attendances.create!(church: church, person: person, attended: attended)
      end

      before { setting.update!(rates: { "group_attendance" => 15 }) }

      it "pays people marked attended, once per meeting" do
        event = meeting
        attend(event, emma)
        attend(event, mark, attended: false)

        2.times { kudos.post_earned_points! }
        expect(balance(emma)).to eq(15)
        expect(balance(mark)).to eq(0)
        expect(emma.points_entries.last).to have_attributes(source: "group_attendance", note: "Attended Rangers")
      end

      it "doesn't pay twice when the sync replaces the attendance row" do
        event = meeting
        attend(event, emma)
        kudos.post_earned_points!
        event.attendances.delete_all
        attend(event, emma)

        kudos.post_earned_points!
        expect(balance(emma)).to eq(15)
      end

      it "skips canceled meetings and ones before the start date" do
        attend(meeting(canceled: true), emma)
        attend(meeting(at: 3.weeks.ago), emma)

        expect(kudos.post_earned_points!).to eq(0)
      end
    end

    context "time served" do
      let(:sunday) { 3.days.ago.change(hour: 9) }
      let(:type)   { church.service_types.create!(pco_service_type_id: "st1", name: "Sunday Services") }

      # A plan with a rehearsal at 7 and services at 9 and 11, an hour each,
      # all scheduled for the band (t1).
      def plan(at: sunday, finished: true)
        type.plans.create!(church: church, pco_plan_id: SecureRandom.hex(4), title: "Faithful", sort_date: at,
                           ends_at: finished ? 1.hour.ago : 1.day.from_now).tap do |p|
          [[-2, "rehearsal"], [0, "service"], [2, "service"]].each_with_index do |(offset, kind), i|
            p.times.create!(church: church, pco_plan_time_id: "pt#{i}", time_type: kind, team_ids: ["t1"],
                            starts_at: at + offset.hours, ends_at: at + offset.hours + 1.hour)
          end
        end
      end

      def schedule(plan, person, status: "C", team: "t1", declined: [])
        plan.plan_people.create!(church: church, person: person, pco_plan_person_id: SecureRandom.hex(4),
                                 status: status, pco_team_id: team, team_name: "Band", position_name: "Guitar",
                                 declined_time_ids: declined)
      end

      before { setting.update!(rates: { "service_hour" => 10 }) }

      it "pays confirmed people for the service times they were scheduled for, once" do
        p = plan
        schedule(p, emma)
        schedule(p, mark, status: "U")

        2.times { kudos.post_earned_points! }
        expect(balance(emma)).to eq(20)
        expect(balance(mark)).to eq(0)
        expect(emma.points_entries.sole).to have_attributes(source: "service", source_id: p.id,
                                                            note: "Served · Sunday Services · Faithful · 2 hours")
      end

      it "counts rehearsals and other times when the church turns that on" do
        setting.update!(count_rehearsals: true)
        schedule(plan, emma)

        kudos.post_earned_points!
        expect(balance(emma)).to eq(30)
      end

      it "leaves out times they declined, and rounds the points" do
        setting.update!(rates: { "service_hour" => 7 })
        p = plan
        p.times.find_by!(pco_plan_time_id: "pt2").update!(ends_at: sunday + 2.hours + 30.minutes)
        schedule(p, emma, declined: ["pt1"])

        kudos.post_earned_points!
        expect(balance(emma)).to eq(4) # 0.5 hours × 7 = 3.5, rounded
        expect(emma.points_entries.sole.note).to end_with("0.5 hours")
      end

      it "counts overlapping hours once for someone on two teams" do
        p = plan
        p.times.update_all(team_ids: %w[t1 t2])
        schedule(p, emma)
        schedule(p, emma, team: "t2")

        expect(kudos.post_earned_points!).to eq(1)
        expect(balance(emma)).to eq(20)
      end

      it "pays the flat rate when their team has no times on the plan" do
        setting.update!(rates: { "service_hour" => 10, "service_flat" => 25 })
        schedule(plan, emma, team: "t9")

        kudos.post_earned_points!
        expect(balance(emma)).to eq(25)
        expect(emma.points_entries.sole.note).to eq("Served · Sunday Services · Faithful")
      end

      it "waits until the plan is over, and skips plans before the start date" do
        schedule(plan(finished: false), emma)
        schedule(plan(at: 3.weeks.ago), emma)

        expect(kudos.post_earned_points!).to eq(0)
      end

      it "doesn't pay again after a re-sync replaces the schedule" do
        p = plan
        schedule(p, emma)
        kudos.post_earned_points!
        p.plan_people.delete_all
        schedule(p, emma)

        kudos.post_earned_points!
        expect(balance(emma)).to eq(20)
      end

      it "saves what was served on the entry, in church time" do
        schedule(plan, emma)
        kudos.post_earned_points!
        setting.update!(count_rehearsals: true)

        serving = emma.points_entries.sole.details["serving"]
        expect(serving).to include("plan" => "Sunday Services · Faithful", "hours" => 2.0, "flat" => false,
                                   "roles" => ["Band — Guitar"])
        clock = ->(t) { t.in_time_zone(Spirely::ChurchTime.zone(church)).strftime("%-l:%M %p") }
        expect(serving["times"].map { |t| t["clock"] }).to eq([clock.(sunday), clock.(sunday + 2.hours)])
      end
    end
  end

  describe "#claim_code!" do
    before { emma && mark }

    def promo(**attrs)
      church.promo_codes.create!(code: "summer", label: "Summer kickoff", points: 50, **attrs)
    end

    it "is case-insensitive and pays the code's points with its label" do
      promo
      entry = kudos.claim_code!(code: " Summer ", pco_person_id: "emma")
      expect(entry).to have_attributes(points: 50, source: "promo_code", note: "Summer kickoff")
      expect(balance(emma)).to eq(50)
    end

    it "can be claimed once per person" do
      promo
      kudos.claim_code!(code: "SUMMER", pco_person_id: "emma")
      expect { kudos.claim_code!(code: "SUMMER", pco_person_id: "emma") }
        .to raise_error(Spirely::Kudos::Error, /Emma already used this code/)
      expect { kudos.claim_code!(code: "SUMMER", pco_person_id: "mark") }.not_to raise_error
    end

    it "stops at max uses" do
      promo(max_uses: 1)
      kudos.claim_code!(code: "SUMMER", pco_person_id: "emma")
      expect { kudos.claim_code!(code: "SUMMER", pco_person_id: "mark") }.to raise_error(Spirely::Kudos::Error, /used up/)
    end

    it "works through its expiry date, not after" do
      code = promo(expires_on: Spirely::ChurchTime.today(church))
      expect { kudos.claim_code!(code: "SUMMER", pco_person_id: "emma") }.not_to raise_error

      code.update!(expires_on: 1.day.ago.to_date)
      expect { kudos.claim_code!(code: "SUMMER", pco_person_id: "mark") }.to raise_error(Spirely::Kudos::Error, /expired/)
    end

    it "refuses unknown and turned-off codes" do
      promo(turned_off_at: Time.current)
      expect { kudos.claim_code!(code: "WINTER", pco_person_id: "emma") }.to raise_error(Spirely::Kudos::Error, /doesn't match/)
      expect { kudos.claim_code!(code: "SUMMER", pco_person_id: "emma") }.to raise_error(Spirely::Kudos::Error, /isn't active/)
    end
  end
end
