require "rails_helper"

RSpec.describe "Small Groups admin endpoints", type: :request do
  let(:church) { create(:church, enabled_modules: ["smallgroups"]) }
  let(:admin) do
    account = create(:account)
    create(:membership, :admin, church: church, account: account)
    account
  end

  before do
    @kids_type = church.group_types.create!(name: "Kids Groups", pco_group_type_id: "gt-k", audience: "children")
    @moms  = church.groups.create!(name: "Moms Connect", pco_group_id: "g1", schedule_text: "Wednesdays at 9:30am",
                                   location_name: "Fellowship Hall")
    @kids  = church.groups.create!(name: "Rangers", pco_group_id: "g2", group_type: @kids_type)
    sarah  = create(:spirely_person, church: church, first_name: "Sarah", last_name: "Johnson", email: "sarah@example.com")
    church.group_memberships.create!(group: @kids, person: sarah, role: "leader", pco_membership_id: "m1", joined_at: 1.year.ago)
    beth   = create(:spirely_person, church: church, first_name: "Beth", last_name: "Carter")
    church.group_memberships.create!(group: @moms, person: beth, role: "member", pco_membership_id: "m2",
                                     joined_at: 1.year.ago, left_at: 2.weeks.ago)
    ana    = create(:spirely_person, church: church, first_name: "Ana", last_name: "Martinez")
    church.group_applications.create!(group: @moms, person: ana, pco_application_id: "a1", status: "pending",
                                      applied_at: 9.days.ago, message: "Can I join?")
    use_tenant_host!(church)
  end

  it "lists groups with flags, audience and group types, flagged groups first" do
    get "/api/v1/admin/groups", headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["groups"].map { |g| g["name"] }).to eq(["Moms Connect", "Rangers"])
    moms = body["groups"].first
    expect(moms["flags"].map { |f| f["key"] }).to contain_exactly("no_leader", "shrinking", "request_waiting")
    expect(moms["members_trend"]).to eq(-1)
    rangers = body["groups"].last
    expect(rangers).to include("audience" => "children", "group_type_name" => "Kids Groups", "leaders" => ["Sarah Johnson"], "flags" => [])
    expect(body["group_types"]).to eq([{ "id" => @kids_type.id, "name" => "Kids Groups", "audience" => "children" }])
  end

  it "returns a group's detail" do
    get "/api/v1/admin/groups/#{@moms.id}", headers: auth_headers(admin)

    body = JSON.parse(response.body)
    expect(body["location_name"]).to eq("Fellowship Hall")
    expect(body["left"].map { |l| l["name"] }).to eq(["Beth Carter"])
    expect(body["pending_requests"].first).to include("name" => "Ana Martinez", "message" => "Can I join?")
    expect(body["pco_url"]).to eq("https://groups.planningcenteronline.com/groups/g1")
  end

  it "summarises health for the overview" do
    get "/api/v1/admin/groups_overview", headers: auth_headers(admin)

    body = JSON.parse(response.body)
    expect(body["needs_attention"]).to include("groups" => 1, "no_leader" => 1, "shrinking" => 1, "request_waiting" => 1)
    expect(body["needs_attention"]["top"].map { |g| g["name"] }).to eq(["Moms Connect"])
    expect(body["membership"]).to eq("weeks" => 8, "joined" => 0, "left" => 1)
    expect(body["groups_count"]).to eq(2)
  end

  it "404s a group from another church" do
    other = create(:church, enabled_modules: ["smallgroups"]).groups.create!(name: "X", pco_group_id: "zz")
    get "/api/v1/admin/groups/#{other.id}", headers: auth_headers(admin)
    expect(response).to have_http_status(:not_found)
  end

  it "404s when Small Groups is off" do
    church.update!(enabled_modules: ["kidsmin"])
    get "/api/v1/admin/groups", headers: auth_headers(admin)
    expect(response).to have_http_status(:not_found)
    expect(JSON.parse(response.body)["code"]).to eq("module_disabled")
  end

  it "forbids non-admins" do
    account = create(:account)
    create(:membership, church: church, account: account, role: "family")
    get "/api/v1/admin/groups_overview", headers: auth_headers(account)
    expect(response).to have_http_status(:forbidden)
  end
end
