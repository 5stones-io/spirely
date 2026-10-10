require "rails_helper"

RSpec.describe Spirely::GroupHealthCalculator do
  let(:church) { create(:church, enabled_modules: ["smallgroups"]) }
  let(:now)    { Time.zone.parse("2026-10-10 12:00") }
  let(:group)  { church.groups.create!(name: "Moms Connect", pco_group_id: "g1") }
  let(:seq)    { [0] }

  def member(role: "member", joined: 1.year.ago, left: nil)
    person = create(:spirely_person, church: church)
    church.group_memberships.create!(group: group, person: person, role: role,
                                     pco_membership_id: "m#{seq[0] += 1}", joined_at: joined, left_at: left)
  end

  def health = described_class.new(church, now: now).health_for(group.reload)
  def flag_keys = health.flags.map(&:key)

  it "flags a group with no current leader" do
    member
    member(role: "leader", left: now - 1.week)
    expect(flag_keys).to include("no_leader")
  end

  it "doesn't flag a group with a current leader" do
    member(role: "leader")
    expect(flag_keys).not_to include("no_leader")
  end

  it "flags shrinking at exactly 25% down over 8 weeks" do
    member(role: "leader")
    2.times { member }
    member(left: now - 2.weeks)             # 4 then, 3 now → 25%
    expect(flag_keys).to include("shrinking")
    expect(health.flags.find { |f| f.key == "shrinking" }.detail).to eq("3 members now, down from 4 over the last 8 weeks.")
  end

  it "doesn't flag shrinking just under 25%" do
    member(role: "leader")
    3.times { member }
    member(left: now - 2.weeks)             # 5 then, 4 now → 20%
    expect(flag_keys).not_to include("shrinking")
  end

  it "doesn't count people who joined in the window as members back then" do
    member(role: "leader")
    member(joined: now - 1.week)
    expect(health.members_then).to eq(1)
    expect(health.trend).to eq(1)
    expect(health.joined.size).to eq(1)
  end

  it "ignores departures from before the window" do
    member(role: "leader")
    member(left: now - 10.weeks)
    expect(health.left).to be_empty
    expect(flag_keys).not_to include("shrinking")
  end

  it "flags a join request only once it has waited 7 days" do
    member(role: "leader")
    ana = create(:spirely_person, church: church, first_name: "Ana", last_name: "Martinez")
    app = church.group_applications.create!(group: group, person: ana, pco_application_id: "a1",
                                            status: "pending", applied_at: now - 6.days)
    expect(flag_keys).not_to include("request_waiting")
    expect(health.pending_requests).to eq([app])

    app.update!(applied_at: now - 9.days)
    waiting = health.flags.find { |f| f.key == "request_waiting" }
    expect(waiting.label).to eq("Request waiting 9 days")
    expect(waiting.detail).to start_with("Ana Martinez asked to join 9 days ago")
  end

  it "lists groups needing attention first" do
    healthy = church.groups.create!(name: "Alpha", pco_group_id: "g2")
    church.group_memberships.create!(group: healthy, person: create(:spirely_person, church: church),
                                     role: "leader", pco_membership_id: "x1", joined_at: 1.year.ago)
    member # Moms Connect: no leader

    names = described_class.new(church, now: now).call.map { |h| h.group.name }
    expect(names).to eq(["Moms Connect", "Alpha"])
  end

  it "skips archived and removed groups" do
    church.groups.create!(name: "Old", pco_group_id: "g3", archived_at: 1.day.ago)
    church.groups.create!(name: "Gone", pco_group_id: "g4", removed_at: 1.day.ago)
    group
    expect(described_class.new(church, now: now).call.map { |h| h.group.name }).to eq(["Moms Connect"])
  end
end
