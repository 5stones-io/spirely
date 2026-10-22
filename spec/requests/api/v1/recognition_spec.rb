require "rails_helper"

# The recognition page (Kudos, 5ST-64).
RSpec.describe "/api/v1/recognition", type: :request do
  let(:church)  { create(:church, enabled_modules: %w[kudos smallgroups]) }
  let(:account) { create(:account, email: "lee@example.com").tap { |a| create(:membership, church: church, account: a) } }
  let!(:lee)    { create(:spirely_person, church: church, first_name: "Lee", last_name: "Smith", email: "lee@example.com", pco_person_id: "lee") }
  let!(:sarah)  { create(:spirely_person, church: church, first_name: "Sarah", last_name: "Mitchell", pco_person_id: "sarah") }
  let!(:stranger) { create(:spirely_person, church: church, first_name: "Sam", last_name: "Stranger", pco_person_id: "sam") }
  let(:group)   { church.groups.create!(name: "Tuesday Night", pco_group_id: "g1") }

  before do
    use_tenant_host!(church)
    church.group_memberships.create!(group: group, person: lee, role: "leader", pco_membership_id: "m1")
    church.group_memberships.create!(group: group, person: sarah, role: "member", pco_membership_id: "m2")
    Spirely::KudosSetting.for(church).update!(rates: { "leader_allowance" => 100 })
  end

  def json = JSON.parse(response.body)

  it "searches only people who share a group or team" do
    get "/api/v1/recognition/recipients", params: { q: "S" }, headers: auth_headers(account)
    expect(json["people"].map { |p| p["name"] }).to eq(["Sarah Mitchell"])
  end

  it "gives a shout-out with points from the allowance, and shows it on the feed" do
    post "/api/v1/shout_outs", params: { to_pco_person_id: "sarah", message: "Thanks for hosting!", points: 20 },
                               headers: auth_headers(account), as: :json

    expect(response).to have_http_status(:created)
    expect(json["shout_out"]).to include("from_name" => "Lee Smith", "points" => 20, "sent_by_me" => true)
    expect(json["allowance"]).to eq("monthly" => 100, "left" => 80)

    get "/api/v1/recognition", headers: auth_headers(account)
    expect(json["feed"].map { |s| s["message"] }).to eq(["Thanks for hosting!"])
    expect(json["allowance"]).to eq("monthly" => 100, "left" => 80)
    expect(json["leaderboards_enabled"]).to be(false)
  end

  it "won't send a shout-out to someone outside your groups and teams" do
    post "/api/v1/shout_outs", params: { to_pco_person_id: "sam", message: "Hi" }, headers: auth_headers(account), as: :json
    expect(response).to have_http_status(:not_found)
    expect(church.shout_outs).to be_empty
  end

  it "keeps leaderboards off until staff turn them on" do
    get "/api/v1/recognition/leaderboard", headers: auth_headers(account)
    expect(response).to have_http_status(:not_found)

    Spirely::KudosSetting.for(church).update!(leaderboards_enabled: true)
    Spirely::Kudos.new(church).award!(pco_person_id: "sarah", points: 30, note: "x", by_account: account)
    get "/api/v1/recognition/leaderboard", params: { scope: "group:#{group.id}" }, headers: auth_headers(account)
    expect(json["rows"]).to eq([{ "rank" => 1, "name" => "Sarah M.", "points" => 30 }])
  end

  describe "for staff" do
    let(:admin) { create(:account, first_name: "Jenna", last_name: "Park").tap { |a| create(:membership, :admin, church: church, account: a) } }

    it "lists every shout-out, hides one and adds points" do
      shout = Spirely::Recognition.new(church).give!(
        viewer: Spirely::Recognition::Viewer.new(account: account, person: lee, staff: false, kid_person_ids: []),
        to_pco_person_id: "sarah", message: "Private thanks", visibility: "private",
      )

      get "/api/v1/admin/kudos/shout_outs", headers: auth_headers(admin)
      expect(json["shout_outs"].sole).to include("message" => "Private thanks", "visibility" => "private")

      patch "/api/v1/admin/kudos/shout_outs/#{shout.id}", params: { hidden: true }, headers: auth_headers(admin), as: :json
      expect(json).to include("hidden" => true, "hidden_by" => "Jenna Park")

      post "/api/v1/admin/kudos/shout_outs/#{shout.id}/points", params: { points: 15 }, headers: auth_headers(admin), as: :json
      expect(json).to include("points" => 15, "points_from" => "staff")
    end

    it "sets the allowance and turns leaderboards on, and can share an award" do
      patch "/api/v1/admin/kudos/settings", params: { leader_allowance: 250, leaderboards_enabled: true },
                                            headers: auth_headers(admin), as: :json
      expect(json).to include("leader_allowance" => 250, "leaderboards_enabled" => true)

      post "/api/v1/admin/kudos/entries", params: { pco_person_id: "sam", points: 40, note: "Parking team MVP", share: true },
                                          headers: auth_headers(admin), as: :json
      expect(church.shout_outs.sole).to have_attributes(message: "Parking team MVP", points: 40, visibility: "public")
    end

    it "is admin-only" do
      get "/api/v1/admin/kudos/shout_outs", headers: auth_headers(account)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
