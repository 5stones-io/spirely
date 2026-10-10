require "rails_helper"

RSpec.describe Spirely::GroupNudgeCalculator do
  include ActiveSupport::Testing::TimeHelpers
  around { |ex| travel_to(Time.zone.parse("2026-10-12 09:00")) { ex.run } }

  let(:church) { create(:church, enabled_modules: ["smallgroups"]) }
  let(:group)  { schedule_group(church) }
  let!(:jen)   { join(church, group, first: "Jen") }
  let!(:other) { join(church, group, first: "Other") }

  # Ten weekly meetings, oldest first, with attendance taken (Other always came).
  def meetings!(jen_pattern)
    jen_pattern.each_with_index.map do |came, i|
      e = meeting(church, group, Time.zone.parse("2026-10-07 19:00") - (jen_pattern.size - 1 - i).weeks)
      church.group_attendances.create!(group_event: e, person: other, attended: true)
      church.group_attendances.create!(group_event: e, person: jen, attended: came == 1)
      e
    end
  end

  def flagged = described_class.new(church).call.map { |r| r.person.first_name }

  it "flags someone who came 4+ of the last 10 and missed the last 2" do
    meetings!([1, 1, 1, 0, 1, 1, 1, 1, 0, 0])
    result = described_class.new(church).call.sole
    expect(result.person).to eq(jen)
    expect(result.metrics).to include("attended" => 7, "considered" => 10, "missed_streak" => 2)
    expect(result.metrics["meetings"].last).to eq("date" => "2026-10-07", "attended" => false)
  end

  it "doesn't flag a single miss" do
    meetings!([1, 1, 1, 1, 1, 1, 1, 1, 1, 0])
    expect(flagged).to be_empty
  end

  it "doesn't flag someone who rarely came anyway" do
    meetings!([1, 0, 1, 0, 0, 1, 0, 0, 0, 0])
    expect(flagged).to be_empty
  end

  it "ignores meetings where nobody took attendance" do
    meetings!([1, 1, 1, 1, 1, 1, 1, 1])
    2.times { |i| meeting(church, group, Time.zone.parse("2026-10-08 19:00") + i.days) } # no attendance rows
    expect(flagged).to be_empty
  end

  it "only counts meetings since the person joined" do
    meetings!([0, 0, 0, 0, 0, 0, 1, 1, 0, 0])
    church.group_memberships.find_by(person: jen).update!(joined_at: Time.zone.parse("2026-09-10"))
    # Joined before the last 4 meetings: came 2 of 4, under the 4-attended bar.
    expect(flagged).to be_empty
  end
end
