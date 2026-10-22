require "rails_helper"

# Kudos phase 2 (5ST-61): points from check-ins, group meetings and promo codes.
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

  describe "#post_attendance_points!" do
    context "check-ins" do
      before { setting.update!(rates: { "checkin" => 10 }) }

      it "pays each check-in once, however many times it runs" do
        check_in(emma)
        check_in(mark)

        expect(kudos.post_attendance_points!).to eq(2)
        expect(kudos.post_attendance_points!).to eq(0)
        expect(balance(emma)).to eq(10)
        expect(emma.points_entries.last).to have_attributes(source: "checkin", note: "Checked in · Sunday Service")
      end

      it "only counts check-ins from the earning start date on" do
        check_in(emma, at: 3.weeks.ago)
        expect(kudos.post_attendance_points!).to eq(0)
      end

      it "pays once per person per event per day" do
        check_in(emma, at: 1.day.ago.change(hour: 9))
        check_in(emma, at: 1.day.ago.change(hour: 11))
        check_in(emma, at: 1.day.ago, pco_event_id: "wednesday", event_name: "Rangers")

        kudos.post_attendance_points!
        expect(balance(emma)).to eq(20)
      end

      it "uses a per-event rate, where 0 means that event doesn't earn" do
        setting.update!(rates: { "checkin" => 10, "checkin_events" => { "wednesday" => 25, "staff" => 0 } })
        check_in(emma, pco_event_id: "wednesday", event_name: "Rangers")
        check_in(mark, pco_event_id: "staff", event_name: "Staff meeting")

        kudos.post_attendance_points!
        expect(balance(emma)).to eq(25)
        expect(balance(mark)).to eq(0)
      end

      it "skips one-time guests but pays regular guests" do
        guest = create(:spirely_person, church: church, first_name: "Visitor", pco_person_id: "v1")
        check_in(guest, kind: "guest")
        check_in(mark, one_time_guest: true)

        kudos.post_attendance_points!
        expect(balance(guest)).to eq(10)
        expect(balance(mark)).to eq(0)
      end

      it "keeps points when Check-Ins later drops the record" do
        check_in(emma).destroy!
        expect(balance(emma)).to eq(0) # nothing posted yet, nothing to keep
        attendance = check_in(emma)
        kudos.post_attendance_points!
        attendance.delete
        kudos.post_attendance_points!
        expect(balance(emma)).to eq(10)
      end

      it "posts nothing when the rates are all 0 or Kudos is off" do
        check_in(emma)
        setting.update!(rates: {})
        expect(kudos.post_attendance_points!).to eq(0)

        setting.update!(rates: { "checkin" => 10 })
        church.update!(enabled_modules: ["smallgroups"])
        expect(kudos.post_attendance_points!).to eq(0)
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

        2.times { kudos.post_attendance_points! }
        expect(balance(emma)).to eq(15)
        expect(balance(mark)).to eq(0)
        expect(emma.points_entries.last).to have_attributes(source: "group_attendance", note: "Attended Rangers")
      end

      it "doesn't pay twice when the sync replaces the attendance row" do
        event = meeting
        attend(event, emma)
        kudos.post_attendance_points!
        event.attendances.delete_all
        attend(event, emma)

        kudos.post_attendance_points!
        expect(balance(emma)).to eq(15)
      end

      it "skips canceled meetings and ones before the start date" do
        attend(meeting(canceled: true), emma)
        attend(meeting(at: 3.weeks.ago), emma)

        expect(kudos.post_attendance_points!).to eq(0)
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
