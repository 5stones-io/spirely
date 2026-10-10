require "rails_helper"

RSpec.describe Spirely::GroupSchedule do
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper

  around do |example|
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    travel_to(Time.zone.parse("2026-10-12 09:00")) { example.run } # a Monday
  ensure
    ActiveJob::Base.queue_adapter = original
  end

  let(:church) { create(:church, enabled_modules: ["smallgroups"]) }
  let(:group)  { schedule_group(church) }
  let!(:leader) { join(church, group, role: "leader", first: "Sarah") }
  let!(:member) { join(church, group, first: "Beth") }
  let(:wed)    { Date.new(2026, 10, 15) } # the group's meeting day (a Thursday)
  let(:admin)  { create(:account, first_name: "Pastor", last_name: "Mike") }
  subject(:schedule) { described_class.new(group) }

  before { meeting(church, group, Time.zone.parse("2026-10-15 09:30")) }

  describe "meeting dates" do
    it "uses upcoming Planning Center events" do
      expect(group.meeting_dates.keys).to eq([wed])
    end

    it "falls back to a weekly repeat when there are no events" do
      group.events.delete_all
      group.update!(cadence_weekday: 3, cadence_anchor_on: Date.new(2026, 10, 1))
      expect(group.meeting_dates.keys).to eq([Date.new(2026, 10, 14), Date.new(2026, 10, 21), Date.new(2026, 10, 28), Date.new(2026, 11, 4)])
    end

    it "keeps an every-other-week repeat aligned to its anchor" do
      group.events.delete_all
      group.update!(cadence_weekday: 3, cadence_interval_weeks: 2, cadence_anchor_on: Date.new(2026, 10, 7))
      expect(group.meeting_dates.keys).to eq([Date.new(2026, 10, 21), Date.new(2026, 11, 4)])
    end

    it "returns no dates with neither events nor a repeat" do
      group.events.delete_all
      expect(group.meeting_dates).to be_empty
    end
  end

  describe "#assign!" do
    it "asks the person, issues a link and emails them" do
      slot = nil
      expect {
        slot = schedule.assign!(meets_on: wed, job: "lead", person: leader, by_account: admin, source: "staff")
      }.to have_enqueued_mail(Spirely::ScheduleMailer, :schedule_request)

      expect(slot).to have_attributes(status: "pending", person: leader, source: "staff", notify_channels: ["email"])
      expect(slot.token_digest).to be_present
      expect(slot.token_expires_at).to be_within(1.second).of(Time.zone.parse("2026-10-15").end_of_day)
    end

    it "also texts when the church's Twilio is verified" do
      leader.update!(phone: "+15551234567")
      allow_any_instance_of(Spirely::ChurchIntegration).to receive(:twilio_verified?).and_return(true)
      sms = instance_double(Spirely::Sms, send: {})
      allow(Spirely::Sms).to receive(:new).and_return(sms)
      Spirely.configuration.encryption_key = SecureRandom.hex(32)
      create(:spirely_church_integration, church: church)

      slot = schedule.assign!(meets_on: wed, job: "lead", person: leader, by_account: admin, source: "staff")
      expect(sms).to have_received(:send).with(hash_including(to: "+15551234567", body: a_string_including("can you lead Moms Connect on Thu Oct 15")))
      expect(slot.notify_channels).to eq(%w[email sms])
    end

    it "only lets leaders lead" do
      expect { schedule.assign!(meets_on: wed, job: "lead", person: member, by_account: admin, source: "staff") }
        .to raise_error(described_class::Error, /leaders can lead/)
    end

    it "lets any member host" do
      slot = schedule.assign!(meets_on: wed, job: "host_home", person: member, by_account: admin, source: "staff")
      expect(slot.person).to eq(member)
    end

    it "refuses people outside the group, dates the group doesn't meet, and jobs it doesn't use" do
      stranger = create(:spirely_person, church: church)
      expect { schedule.assign!(meets_on: wed, job: "host_home", person: stranger, by_account: admin, source: "staff") }
        .to raise_error(described_class::Error, /members of this group/)
      expect { schedule.assign!(meets_on: wed + 1, job: "lead", person: leader, by_account: admin, source: "staff") }
        .to raise_error(described_class::Error, /doesn't meet/)
      group.update!(schedule_jobs: ["lead"])
      expect { schedule.assign!(meets_on: wed, job: "refreshments", person: member, by_account: admin, source: "staff") }
        .to raise_error(described_class::Error, /doesn't schedule/)
    end

    it "doesn't re-send when asking the same person again" do
      slot = schedule.assign!(meets_on: wed, job: "lead", person: leader, by_account: admin, source: "staff")
      digest = slot.token_digest
      expect { schedule.assign!(meets_on: wed, job: "lead", person: leader, by_account: admin, source: "staff") }
        .not_to have_enqueued_mail(Spirely::ScheduleMailer, :schedule_request)
      expect(slot.reload.token_digest).to eq(digest)
    end
  end

  describe "#sign_up!" do
    it "confirms straight away, with no link" do
      slot = schedule.sign_up!(meets_on: wed, job: "refreshments", person: member)
      expect(slot).to have_attributes(status: "accepted", source: "self", token_digest: nil)
    end

    it "is refused when someone else has the spot, allowed after they decline" do
      other = join(church, group, first: "Kara")
      slot = schedule.assign!(meets_on: wed, job: "refreshments", person: other, by_account: admin, source: "staff")
      expect { schedule.sign_up!(meets_on: wed, job: "refreshments", person: member) }
        .to raise_error(described_class::Error, /already has this spot/)

      described_class.respond!(slot, "decline")
      expect(schedule.sign_up!(meets_on: wed, job: "refreshments", person: member).person).to eq(member)
    end
  end

  describe ".respond!" do
    it "tells the head leader when someone declines" do
      head = join(church, group, role: "leader", first: "Head", head: true)
      slot = schedule.assign!(meets_on: wed, job: "host_home", person: member, by_account: admin, source: "staff")

      expect { described_class.respond!(slot, "decline") }
        .to have_enqueued_mail(Spirely::ScheduleMailer, :declined).with(slot, head.email)
      expect(slot.reload.status).to eq("declined")
    end

    it "falls back to the church's admins with no head leader" do
      join(church, group, role: "leader", first: "Second") # two leaders, none marked
      create(:membership, :admin, church: church, account: admin)
      slot = schedule.assign!(meets_on: wed, job: "host_home", person: member, by_account: admin, source: "staff")

      expect { described_class.respond!(slot, "decline") }
        .to have_enqueued_mail(Spirely::ScheduleMailer, :declined).with(slot, admin.email)
    end

    it "does nothing new when the answer repeats" do
      slot = schedule.assign!(meets_on: wed, job: "lead", person: leader, by_account: admin, source: "staff")
      described_class.respond!(slot, "accept")
      responded = slot.reload.responded_at
      travel 1.minute
      described_class.respond!(slot, "accept")
      expect(slot.reload.responded_at).to eq(responded)
    end
  end

  describe "#unassign!" do
    it "reopens the slot and kills its link" do
      slot = schedule.assign!(meets_on: wed, job: "lead", person: leader, by_account: admin, source: "staff")
      schedule.unassign!(meets_on: wed, job: "lead")
      expect(slot.reload).to have_attributes(status: "open", person: nil, token_digest: nil)
    end
  end

  it "makes the only leader the head leader" do
    expect(group.head_leader).to eq(leader)
    join(church, group, role: "leader", first: "Second")
    expect(group.reload.head_leader).to be_nil
  end
end
