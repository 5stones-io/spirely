require "rails_helper"

RSpec.describe "/api/v1/admin/kudos", type: :request do
  let(:church) { create(:church, enabled_modules: ["kudos"]) }
  let(:admin)  { create(:account, first_name: "Pastor", last_name: "Mike").tap { |a| create(:membership, :admin, church: church, account: a) } }
  let!(:sarah) { create(:spirely_person, church: church, first_name: "Sarah", last_name: "Mitchell", pco_person_id: "p1") }
  let!(:emma)  { create(:spirely_person, church: church, first_name: "Emma", last_name: "Johnson", pco_person_id: "p2", child: true) }

  before { use_tenant_host!(church) }

  def json = JSON.parse(response.body)

  def award(person, points, note = "Thanks")
    Spirely::Kudos.new(church).award!(pco_person_id: person.pco_person_id, points: points, note: note, by_account: admin)
  end

  it "shows the overview" do
    award(sarah, 100)
    award(emma, 50)
    award(emma, -10, "Correction")

    get "/api/v1/admin/kudos", headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(json).to include("points_held" => 140, "people_count" => 2)
    expect(json["month"]).to include("awarded" => 150, "awards_count" => 2, "awarders_count" => 1, "deducted" => 10, "deductions_count" => 1)
    expect(json["recent"].first).to include("points" => -10, "note" => "Correction", "by" => "Pastor Mike")
  end

  it "lists people with points, highest balance first, filtered by audience" do
    award(sarah, 100)
    award(emma, 300)

    get "/api/v1/admin/kudos/people", headers: auth_headers(admin)
    expect(json["people"].map { |p| [p["name"], p["balance"]] }).to eq([["Emma Johnson", 300], ["Sarah Mitchell", 100]])
    expect(json["meta"]["total_count"]).to eq(2)

    get "/api/v1/admin/kudos/people", params: { audience: "adults" }, headers: auth_headers(admin)
    expect(json["people"].map { |p| p["name"] }).to eq(["Sarah Mitchell"])
  end

  it "searches everyone, with or without points" do
    get "/api/v1/admin/kudos/people", params: { q: "emma" }, headers: auth_headers(admin)
    expect(json["people"]).to match([a_hash_including("pco_person_id" => "p2", "balance" => 0, "kid" => true)])
  end

  it "shows one person's balance and history" do
    award(emma, 50)
    award(emma, -20, "Entered twice")

    get "/api/v1/admin/kudos/people/p2", headers: auth_headers(admin)

    expect(json).to include("name" => "Emma Johnson", "balance" => 30, "earned" => 50, "deducted" => 20, "more_history" => false)
    expect(json["history"].map { |e| [e["points"], e["balance_after"]] }).to eq([[-20, 30], [50, 50]])
  end

  it "awards and deducts points" do
    post "/api/v1/admin/kudos/entries", params: { pco_person_id: "p1", points: 25, note: "Set up chairs" },
         headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:created)
    expect(json).to include("points" => 25, "balance" => 25)

    post "/api/v1/admin/kudos/entries", params: { pco_person_id: "p1", points: -30, note: "Too many" },
         headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(json["error"]).to match(/only has 25 points/)
  end

  it "updates the earning start date" do
    patch "/api/v1/admin/kudos/settings", params: { earning_starts_on: "2026-09-01" }, headers: auth_headers(admin), as: :json
    expect(json).to eq("earning_starts_on" => "2026-09-01")
    expect(church.kudos_setting.earning_starts_on).to eq(Date.new(2026, 9, 1))
  end

  it "is admin-only" do
    family_account = create(:account).tap { |a| create(:membership, church: church, account: a) }
    post "/api/v1/admin/kudos/entries", params: { pco_person_id: "p1", points: 25, note: "x" },
         headers: auth_headers(family_account), as: :json
    expect(response).to have_http_status(:forbidden)
    expect(church.points_entries.count).to eq(0)
  end

  it "404s when Kudos is off" do
    church.update!(enabled_modules: ["kidsmin"])
    get "/api/v1/admin/kudos", headers: auth_headers(admin)
    expect(response).to have_http_status(:not_found)
  end
end
