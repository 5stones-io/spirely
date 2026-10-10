require "rails_helper"

RSpec.describe "Small Groups follow-ups", type: :request do
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper
  around do |ex|
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    travel_to(Time.zone.parse("2026-10-12 09:00")) { ex.run }
  ensure
    ActiveJob::Base.queue_adapter = original
  end

  let(:church) { create(:church, enabled_modules: ["smallgroups"]) }
  let(:admin)  { create(:account, first_name: "Pastor", last_name: "Mike").tap { |a| create(:membership, :admin, church: church, account: a) } }
  let(:group)  { schedule_group(church) }
  let!(:sarah) { join(church, group, role: "leader", first: "Sarah", email: "sarah@example.com") }
  let!(:jen)   { join(church, group, first: "Jen", phone: "(239) 555-0148") }

  before do
    10.times do |i|
      e = meeting(church, group, Time.zone.parse("2026-10-07 19:00") - (9 - i).weeks)
      church.group_attendances.create!(group_event: e, person: sarah, attended: true)
      church.group_attendances.create!(group_event: e, person: jen, attended: i < 8)
    end
    use_tenant_host!(church)
  end

  def sync! = Spirely::GroupNudgeSyncJob.perform_now(church.id)

  it "opens a follow-up owned by the head leader, refreshes it, and never closes it on its own" do
    sync!
    nudge = church.group_nudges.sole
    expect(nudge).to have_attributes(person: jen, owner_person: sarah, resolved_at: nil)
    expect(nudge.notes.sole.body).to eq("Follow-up created: missed 2 meetings in a row.")

    e = meeting(church, group, Time.zone.parse("2026-10-11 19:00"))
    church.group_attendances.create!(group_event: e, person: sarah, attended: true)
    church.group_attendances.create!(group_event: e, person: jen, attended: false)
    sync!
    expect(nudge.reload.metrics["missed_streak"]).to eq(3)
    expect(church.group_nudges.count).to eq(1)
  end

  it "lists open follow-ups and shows details" do
    sync!
    get "/api/v1/admin/group_nudges", headers: auth_headers(admin)
    body = JSON.parse(response.body)
    expect(body["open_count"]).to eq(1)
    expect(body["follow_ups"].first).to include("person" => { "id" => jen.id, "name" => "Jen Test" }, "owner" => { "id" => sarah.id, "name" => "Sarah Test" })

    get "/api/v1/admin/group_nudges/#{church.group_nudges.sole.id}", headers: auth_headers(admin)
    detail = JSON.parse(response.body)
    expect(detail["contact"]["phone"]).to eq("(239) 555-0148")
    expect(detail["owner_options"].map { |o| o["name"] }).to eq(["Sarah Test"])
    expect(detail["history"].size).to eq(1)
  end

  it "keeps it open on a note, closes it on an outcome" do
    sync!
    nudge = church.group_nudges.sole
    post "/api/v1/admin/group_nudges/#{nudge.id}/notes", params: { body: "Texted her" }, headers: auth_headers(admin), as: :json
    expect(nudge.reload).to be_open
    post "/api/v1/admin/group_nudges/#{nudge.id}/notes", params: { outcome: "contacted", body: "Talked Sunday" }, headers: auth_headers(admin), as: :json
    expect(nudge.reload).to have_attributes(resolution: "contacted", resolved_by_account: admin)
    expect(nudge.notes.first).to have_attributes(author_name: "Pastor Mike", outcome: "contacted")

    post "/api/v1/admin/group_nudges/#{nudge.id}/notes", params: {}, headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "shows when they've come back" do
    sync!
    e = meeting(church, group, Time.zone.parse("2026-10-11 19:00"))
    church.group_attendances.create!(group_event: e, person: jen, attended: true)
    get "/api/v1/admin/group_nudges", headers: auth_headers(admin)
    expect(JSON.parse(response.body)["follow_ups"].first["came_back_on"]).to eq("2026-10-11")
  end

  it "only lets a group leader own a follow-up" do
    sync!
    nudge = church.group_nudges.sole
    patch "/api/v1/admin/group_nudges/#{nudge.id}", params: { owner_person_id: jen.id }, headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    patch "/api/v1/admin/group_nudges/#{nudge.id}", params: { owner_person_id: "" }, headers: auth_headers(admin), as: :json
    expect(nudge.reload.owner_person).to be_nil
  end

  it "counts follow-ups on the overview" do
    sync!
    get "/api/v1/admin/groups_overview", headers: auth_headers(admin)
    expect(JSON.parse(response.body)["follow_ups"]).to include("open" => 1, "unassigned" => 0)
  end

  it "shows a group's leaders its follow-ups in My Groups, and lets them log" do
    sync!
    leader = create(:account, email: "sarah@example.com")
    get "/api/v1/my_groups", headers: auth_headers(leader)
    nudge_id = JSON.parse(response.body)["follow_ups"].sole["id"]

    post "/api/v1/my_groups/follow_ups/#{nudge_id}/notes", params: { outcome: "returned" }, headers: auth_headers(leader), as: :json
    expect(response).to have_http_status(:ok)
    expect(church.group_nudges.find(nudge_id).resolution).to eq("returned")
  end

  it "doesn't show members other people's follow-ups" do
    sync!
    member = create(:account, email: jen.email)
    get "/api/v1/my_groups", headers: auth_headers(member)
    expect(JSON.parse(response.body)["follow_ups"]).to be_empty
    get "/api/v1/my_groups/follow_ups/#{church.group_nudges.sole.id}", headers: auth_headers(member)
    expect(response).to have_http_status(:not_found)
  end

end
