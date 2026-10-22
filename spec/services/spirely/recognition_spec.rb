require "rails_helper"

# Kudos phase 5 (5ST-64): shout-outs, the leader allowance and leaderboards.
RSpec.describe Spirely::Recognition do
  include ActiveSupport::Testing::TimeHelpers

  let(:church)      { create(:church, enabled_modules: %w[kudos smallgroups]) }
  let(:recognition) { described_class.new(church) }
  let(:kudos)       { Spirely::Kudos.new(church) }
  let(:setting)     { Spirely::KudosSetting.for(church) }
  let(:staff)       { create(:account, first_name: "Jenna", last_name: "Park") }
  let(:lee_account) { create(:account, email: "lee@example.com") }
  let(:lee)   { create(:spirely_person, church: church, first_name: "Lee", last_name: "Smith", pco_person_id: "lee") }
  let(:sarah) { create(:spirely_person, church: church, first_name: "Sarah", last_name: "Mitchell", pco_person_id: "sarah") }
  let(:emma)  { create(:spirely_person, church: church, first_name: "Emma", last_name: "Johnson", pco_person_id: "emma", child: true) }
  let(:group) { church.groups.create!(name: "Tuesday Night", pco_group_id: "g1") }

  def viewer(account: nil, person: nil, staff: false, kids: [])
    described_class::Viewer.new(account: account, person: person, staff: staff, kid_person_ids: kids.map(&:id))
  end

  def lead!(person)
    church.group_memberships.create!(group: group, person: person, role: "leader", pco_membership_id: "m-#{person.id}")
  end

  let(:lee_viewer) { viewer(account: lee_account, person: lee) }

  before do
    setting.update!(earning_starts_on: 1.month.ago.to_date)
    lee && sarah && emma
  end

  describe "#give!" do
    it "sends a shout-out with no points by default" do
      shout = recognition.give!(viewer: lee_viewer, to_pco_person_id: "sarah", message: "Thanks for setting up!")
      expect(shout).to have_attributes(from_name: "Lee Smith", to_person: sarah, visibility: "public", points: 0, points_entry: nil)
    end

    it "won't send one to yourself, or an empty one" do
      expect { recognition.give!(viewer: lee_viewer, to_pco_person_id: "lee", message: "Me!") }
        .to raise_error(Spirely::Kudos::Error, "You can't send yourself a shout-out.")
      sarah
      expect { recognition.give!(viewer: lee_viewer, to_pco_person_id: "sarah", message: "  ") }
        .to raise_error(Spirely::Kudos::Error, "Say what you're thanking them for.")
    end

    it "only lets leaders give points" do
      setting.update!(rates: { "leader_allowance" => 100 })
      sarah
      expect { recognition.give!(viewer: lee_viewer, to_pco_person_id: "sarah", message: "Thanks", points: 10) }
        .to raise_error(Spirely::Kudos::Error, "Only group and team leaders can give points with a shout-out.")
    end
  end

  describe "the leader allowance" do
    before do
      setting.update!(rates: { "leader_allowance" => 100 })
      lead!(lee)
      sarah
    end

    it "pays points out of the allowance, not the leader's own balance" do
      recognition.give!(viewer: lee_viewer, to_pco_person_id: "sarah", message: "Great job", points: 60)

      expect(kudos.totals(sarah)[:balance]).to eq(60)
      expect(kudos.totals(lee)[:balance]).to eq(0)
      expect(sarah.points_entries.sole).to have_attributes(source: "shout_out", note: "Shout-out from Lee Smith")
      expect(recognition.allowance_left(lee)).to eq(40)
    end

    it "won't go past what's left this month" do
      recognition.give!(viewer: lee_viewer, to_pco_person_id: "sarah", message: "Great job", points: 60)
      expect { recognition.give!(viewer: lee_viewer, to_pco_person_id: "sarah", message: "Again", points: 50) }
        .to raise_error(Spirely::Kudos::Error, "You have 40 points left to give this month.")
    end

    it "starts fresh each month, without rolling over" do
      travel_to 1.month.ago do
        recognition.give!(viewer: lee_viewer, to_pco_person_id: "sarah", message: "Last month", points: 30)
      end
      expect(recognition.allowance_left(lee)).to eq(100)
    end

    it "counts Services team leaders too" do
      church.service_team_leaders.create!(person: sarah, pco_team_id: "t1", team_name: "Band")
      expect(recognition.leader?(sarah)).to be(true)
      expect(recognition.allowance_left(sarah)).to eq(100)
    end
  end

  describe "who sees what" do
    let(:parent_account) { create(:account) }
    let(:other) { viewer(account: create(:account), person: create(:spirely_person, church: church, pco_person_id: "x")) }

    it "shows private shout-outs only to the sender and recipient" do
      sarah_viewer = viewer(account: create(:account), person: sarah)
      shout = recognition.give!(viewer: lee_viewer, to_pco_person_id: "sarah", message: "Just between us", visibility: "private")

      expect(recognition.visible_to?(shout, lee_viewer)).to be(true)
      expect(recognition.visible_to?(shout, sarah_viewer)).to be(true)
      expect(recognition.visible_to?(shout, other)).to be(false)
      expect(recognition.visible_to?(shout, viewer(account: staff, staff: true))).to be(true)
      expect(recognition.feed).to be_empty
    end

    it "keeps shout-outs to kids to staff, the sender and the kid's parents, even public ones" do
      shout = recognition.give!(viewer: lee_viewer, to_pco_person_id: "emma", message: "Great memory verse!")

      expect(recognition.visible_to?(shout, viewer(account: parent_account, kids: [emma]))).to be(true)
      expect(recognition.visible_to?(shout, lee_viewer)).to be(true)
      expect(recognition.visible_to?(shout, other)).to be(false)
      expect(recognition.feed).to be_empty
      expect(recognition.mine(viewer(account: parent_account, kids: [emma]))).to eq([shout])
    end

    it "takes hidden shout-outs off the feed for everyone but staff" do
      shout = recognition.give!(viewer: lee_viewer, to_pco_person_id: "sarah", message: "Thanks!")
      expect(recognition.feed).to eq([shout])

      recognition.hide!(shout, hidden: true, by_account: staff)

      expect(recognition.feed).to be_empty
      expect(recognition.visible_to?(shout, other)).to be(false)
      expect(shout.hidden_by_name).to eq("Jenna Park")
    end
  end

  describe "staff" do
    it "add points to a shout-out once" do
      sarah
      shout = recognition.give!(viewer: lee_viewer, to_pco_person_id: "sarah", message: "Thanks!")
      recognition.add_points!(shout, points: 25, by_account: staff)

      expect(shout.reload).to have_attributes(points: 25, points_from: "staff")
      expect(kudos.totals(sarah)[:balance]).to eq(25)
      expect { recognition.add_points!(shout, points: 5, by_account: staff) }
        .to raise_error(Spirely::Kudos::Error, "That shout-out already came with points.")
    end

    it "can share an award on the feed" do
      sarah
      kudos.award!(pco_person_id: "sarah", points: 50, note: "Ran the coffee bar all fall", by_account: staff, share: true)
      expect(recognition.feed.sole).to have_attributes(from_name: "Jenna Park", message: "Ran the coffee bar all fall", points: 50)
      expect(kudos.totals(sarah)[:balance]).to eq(50)
    end
  end

  describe "#leaderboard" do
    before do
      kudos.award!(pco_person_id: "sarah", points: 90, note: "x", by_account: staff)
      kudos.award!(pco_person_id: "lee", points: 40, note: "x", by_account: staff)
      kudos.award!(pco_person_id: "emma", points: 300, note: "x", by_account: staff)
    end

    it "ranks adults and kids separately, by first name and last initial" do
      expect(recognition.leaderboard).to eq([{ rank: 1, name: "Sarah M.", points: 90 }, { rank: 2, name: "Lee S.", points: 40 }])
      expect(recognition.leaderboard(kids: true)).to eq([{ rank: 1, name: "Emma J.", points: 300 }])
    end

    it "leaves off people who opted out, and doesn't count refunds or spending" do
      sarah.update!(kudos_leaderboard_opt_out: true)
      church.points_entries.create!(person: lee, points: 500, source: "refund", note: "Refund", occurred_on: Date.current)
      expect(recognition.leaderboard.map { |r| r[:name] }).to eq(["Lee S."])
      expect(recognition.leaderboard.first[:points]).to eq(40)
    end

    it "narrows to one group" do
      church.group_memberships.create!(group: group, person: lee, role: "member", pco_membership_id: "m1")
      expect(recognition.leaderboard(group_id: group.id).map { |r| r[:name] }).to eq(["Lee S."])
    end

    it "covers the year as well as the month" do
      travel_to Date.current.beginning_of_year + 1.day do
        kudos.award!(pco_person_id: "lee", points: 100, note: "Early", by_account: staff)
      end
      expect(recognition.leaderboard(period: "year").first).to include(name: "Lee S.", points: 140)
    end
  end
end
