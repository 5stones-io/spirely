require "rails_helper"

RSpec.describe "My Groups", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:church) { create(:church, enabled_modules: ["smallgroups"]) }
  let(:group)  { schedule_group(church) }
  let!(:sarah) { join(church, group, role: "leader", first: "Sarah", email: "sarah@example.com") }
  let!(:beth)  { join(church, group, first: "Beth", email: "beth@example.com") }
  let(:sarah_account) { create(:account, email: "sarah@example.com") }
  let(:beth_account)  { create(:account, email: "beth@example.com") }

  around { |ex| travel_to(Time.zone.parse("2026-10-12 09:00")) { ex.run } }

  before do
    meeting(church, group, Time.zone.parse("2026-10-15 09:30"))
    allow(Spirely::ScheduleNotifier).to receive(:request).and_return(["email"])
    use_tenant_host!(church)
  end

  it "shows the leader their groups and pending requests" do
    Spirely::GroupSchedule.new(group).assign!(meets_on: Date.new(2026, 10, 15), job: "lead", person: sarah, by_account: nil, source: "staff")
    get "/api/v1/my_groups", headers: auth_headers(sarah_account)

    body = JSON.parse(response.body)
    expect(body["requests"].map { |r| [r["group"]["name"], r["job"]] }).to eq([["Moms Connect", "lead"]])
    g = body["groups"].first
    expect(g).to include("role" => "leader", "head_leader" => true)
    expect(g["people"]).to be_present
    lead = g["meetings"].first["slots"].find { |s| s["job"] == "lead" }
    expect(lead).to include("mine" => true, "can_sign_up" => false)
  end

  it "lets a member sign up for hosting but not leading" do
    get "/api/v1/my_groups", headers: auth_headers(beth_account)
    slots = JSON.parse(response.body)["groups"].first["meetings"].first["slots"]
    expect(slots.to_h { |s| [s["job"], s["can_sign_up"]] }).to eq("lead" => false, "host_home" => true, "refreshments" => true)

    post "/api/v1/my_groups/groups/#{group.id}/sign_up", params: { meets_on: "2026-10-15", job: "host_home" },
         headers: auth_headers(beth_account), as: :json
    expect(JSON.parse(response.body)).to include("status" => "accepted", "source" => "self")

    post "/api/v1/my_groups/groups/#{group.id}/sign_up", params: { meets_on: "2026-10-15", job: "lead" },
         headers: auth_headers(beth_account), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "lets only the head leader schedule the group" do
    put "/api/v1/my_groups/groups/#{group.id}/schedule_slot", params: { meets_on: "2026-10-15", job: "refreshments", person_id: beth.id },
        headers: auth_headers(beth_account), as: :json
    expect(response).to have_http_status(:forbidden)

    put "/api/v1/my_groups/groups/#{group.id}/schedule_slot", params: { meets_on: "2026-10-15", job: "refreshments", person_id: beth.id },
        headers: auth_headers(sarah_account), as: :json
    expect(JSON.parse(response.body)).to include("status" => "pending", "source" => "head_leader")
  end

  it "answers a request while signed in" do
    slot = Spirely::GroupSchedule.new(group).assign!(meets_on: Date.new(2026, 10, 15), job: "host_home", person: beth, by_account: nil, source: "staff")
    post "/api/v1/my_groups/slots/#{slot.id}/respond", params: { choice: "accept" }, headers: auth_headers(beth_account), as: :json
    expect(slot.reload.status).to eq("accepted")
  end

  it "says so when the account can't be matched to Planning Center" do
    get "/api/v1/my_groups", headers: auth_headers(create(:account))
    expect(response).to have_http_status(:not_found)
    expect(JSON.parse(response.body)["code"]).to eq("person_not_found")
  end

  it "reports group roles on /me" do
    get "/api/v1/me", headers: auth_headers(sarah_account)
    body = JSON.parse(response.body)
    expect(body["role"]).to eq("group_leader")
    expect(body["capabilities"]).to eq(["group_leader"])

    get "/api/v1/me", headers: auth_headers(beth_account)
    expect(JSON.parse(response.body)["capabilities"]).to eq(["group_member"])
  end
end
