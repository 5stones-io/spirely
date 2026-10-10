require "rails_helper"

RSpec.describe Spirely::ScheduleMailer do
  let(:church) { create(:church, name: "Grace Church", enabled_modules: ["smallgroups"]) }
  let(:group)  { schedule_group(church) }
  let(:sarah)  { join(church, group, role: "leader", first: "Sarah", email: "sarah@example.com") }
  let(:slot) do
    church.group_schedule_assignments.create!(group: group, meets_on: Date.new(2026, 10, 15), job: "lead", person: sarah,
                                              status: "pending", assigned_by_account: create(:account, first_name: "Pastor", last_name: "Mike"))
  end

  it "asks with Accept/Decline links to the confirm page" do
    mail = described_class.schedule_request(slot, "https://grace.example/schedule/r/tok123")
    expect(mail.to).to eq(["sarah@example.com"])
    expect(mail.subject).to eq("Can you lead Moms Connect on Thu Oct 15?")
    html = mail.html_part.body.to_s
    expect(html).to include("Pastor Mike scheduled you to lead Moms Connect")
    expect(html).to include("https://grace.example/schedule/r/tok123?choice=accept")
    expect(html).to include("https://grace.example/schedule/r/tok123?choice=decline")
    expect(mail.text_part.body.to_s).to include("Fellowship Hall")
  end

  it "tells someone a spot was declined" do
    mail = described_class.declined(slot, "head@example.com")
    expect(mail.to).to eq(["head@example.com"])
    expect(mail.subject).to eq("Sarah Test can't lead Moms Connect on Thu Oct 15")
  end
end
