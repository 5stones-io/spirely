require "rails_helper"

RSpec.describe "Schedule accept/decline links", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:church) { create(:church, enabled_modules: ["smallgroups"]) }
  let(:group)  { schedule_group(church) }
  let!(:leader) { join(church, group, role: "leader", first: "Sarah") }
  let(:day)    { Date.new(2026, 10, 15) }

  around { |ex| travel_to(Time.zone.parse("2026-10-12 09:00")) { ex.run } }

  before do
    meeting(church, group, Time.zone.parse("2026-10-15 09:30"))
    allow(Spirely::ScheduleNotifier).to receive(:request) { |slot, token| @token = token; ["email"] }
    @slot = Spirely::GroupSchedule.new(group).assign!(meets_on: day, job: "lead", person: leader, by_account: nil, source: "staff")
    use_tenant_host!(church)
  end

  it "shows the request without answering it (no sign-in)" do
    get "/api/v1/schedule_responses/#{@token}"
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body).to include("first_name" => "Sarah", "group_name" => "Moms Connect", "job" => "lead",
                            "status" => "pending", "answerable" => true, "where" => "Fellowship Hall")
    expect(body["when"]).to eq("Thursday, Oct 15 · 9:30am")
    expect(@slot.reload.status).to eq("pending")
  end

  it "records the answer on POST, and lets them change their mind" do
    post "/api/v1/schedule_responses/#{@token}", params: { choice: "accept" }, as: :json
    expect(JSON.parse(response.body)["status"]).to eq("accepted")
    post "/api/v1/schedule_responses/#{@token}", params: { choice: "decline" }, as: :json
    expect(@slot.reload.status).to eq("declined")
  end

  it "stops working once the spot is given to someone else" do
    old = @token
    other = join(church, group, role: "leader", first: "Mark")
    Spirely::GroupSchedule.new(group).assign!(meets_on: day, job: "lead", person: other, by_account: nil, source: "staff")

    get "/api/v1/schedule_responses/#{old}"
    expect(response).to have_http_status(:not_found)
  end

  it "won't take answers after the meeting day" do
    travel_to Time.zone.parse("2026-10-16 08:00")
    post "/api/v1/schedule_responses/#{@token}", params: { choice: "accept" }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(@slot.reload.status).to eq("pending")
  end

  it "404s an unknown token" do
    get "/api/v1/schedule_responses/not-a-real-token"
    expect(response).to have_http_status(:not_found)
  end
end
