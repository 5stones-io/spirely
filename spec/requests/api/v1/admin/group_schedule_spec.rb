require "rails_helper"

RSpec.describe "Small Groups schedule (staff)", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:church) { create(:church, enabled_modules: ["smallgroups"]) }
  let(:admin)  { create(:account).tap { |a| create(:membership, :admin, church: church, account: a) } }
  let(:group)  { schedule_group(church) }
  let!(:leader) { join(church, group, role: "leader", first: "Sarah") }
  let!(:member) { join(church, group, first: "Beth") }

  around { |ex| travel_to(Time.zone.parse("2026-10-12 09:00")) { ex.run } }

  before do
    meeting(church, group, Time.zone.parse("2026-10-15 09:30"))
    allow(Spirely::ScheduleNotifier).to receive(:request).and_return(["email"])
    use_tenant_host!(church)
  end

  it "returns the grid with eligible people and coverage" do
    Spirely::GroupSchedule.new(group).sign_up!(meets_on: Date.new(2026, 10, 15), job: "lead", person: leader)
    get "/api/v1/admin/group_schedule", headers: auth_headers(admin)

    body = JSON.parse(response.body)
    g = body["groups"].first
    expect(g["jobs"]).to eq(%w[lead host_home refreshments])
    expect(g["people"]["lead"].map { |p| p["name"] }).to eq(["Sarah Test"])
    expect(g["people"]["hosting"].size).to eq(2)
    slots = g["meetings"].first["slots"]
    expect(slots.map { |s| [s["job"], s["status"]] }).to eq([%w[lead accepted], %w[host_home open], %w[refreshments open]])
    expect(body["summary"]).to include("meetings" => 1, "covered" => 0, "open_slots" => 2)
  end

  it "assigns, re-sends and clears a slot" do
    put "/api/v1/admin/groups/#{group.id}/schedule_slot", params: { meets_on: "2026-10-15", job: "host_home", person_id: member.id },
        headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to include("status" => "pending", "source" => "staff")

    post "/api/v1/admin/groups/#{group.id}/schedule_slot/resend", params: { meets_on: "2026-10-15", job: "host_home" },
         headers: auth_headers(admin), as: :json
    expect(Spirely::ScheduleNotifier).to have_received(:request).twice

    delete "/api/v1/admin/groups/#{group.id}/schedule_slot", params: { meets_on: "2026-10-15", job: "host_home" },
           headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:no_content)
    expect(group.schedule_assignments.find_by(job: "host_home").status).to eq("open")
  end

  it "explains why an assignment isn't allowed" do
    put "/api/v1/admin/groups/#{group.id}/schedule_slot", params: { meets_on: "2026-10-15", job: "lead", person_id: member.id },
        headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["error"]).to match(/leaders can lead/)
  end

  it "saves schedule settings" do
    second = join(church, group, role: "leader", first: "Mark")
    patch "/api/v1/admin/groups/#{group.id}", params: { head_leader_person_id: second.id, schedule_jobs: ["refreshments"], cadence_weekday: 3 },
          headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:ok)
    schedule = JSON.parse(response.body)["schedule"]
    expect(schedule).to include("jobs" => %w[lead refreshments], "cadence_weekday" => 3, "dates_source" => "planning_center")
    expect(schedule["head_leader"]["name"]).to eq("Mark Test")
  end

  it "won't make a non-leader head leader" do
    patch "/api/v1/admin/groups/#{group.id}", params: { head_leader_person_id: member.id }, headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:not_found)
  end

  it "flags groups with unled upcoming meetings once they use the schedule" do
    get "/api/v1/admin/groups", headers: auth_headers(admin)
    expect(JSON.parse(response.body)["groups"].first["flags"]).to be_empty

    Spirely::GroupSchedule.new(group).sign_up!(meets_on: Date.new(2026, 10, 15), job: "refreshments", person: member)
    get "/api/v1/admin/groups", headers: auth_headers(admin)
    expect(JSON.parse(response.body)["groups"].first["flags"].map { |f| f["key"] }).to eq(["lead_unscheduled"])

    get "/api/v1/admin/groups_overview", headers: auth_headers(admin)
    expect(JSON.parse(response.body)["schedule"]).to include("meetings" => 1, "open_slots" => 2)
  end
end
