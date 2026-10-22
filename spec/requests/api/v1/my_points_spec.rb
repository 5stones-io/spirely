require "rails_helper"

RSpec.describe "/api/v1/my_points", type: :request do
  let(:church)  { create(:church, enabled_modules: ["kudos"]) }
  let(:account) { create(:account, email: "mark@example.com") }
  let(:staff)   { create(:account) }
  let!(:family) do
    create(:spirely_family, church: church, account: account, family_name: "Johnson", pco_person_id: "dad",
                            primary_contact_first_name: "Mark", primary_contact_last_name: "Johnson")
  end
  let!(:emma) { create(:spirely_child, family: family, first_name: "Emma", last_name: "Johnson", pco_person_id: "emma") }
  let!(:noah) { create(:spirely_child, family: family, first_name: "Noah", last_name: "Johnson", pco_person_id: nil) }

  before { use_tenant_host!(church) }

  def json = JSON.parse(response.body)
  def kudos = Spirely::Kudos.new(church)

  it "shows the parent's own points and each of their kids'" do
    kudos.award!(pco_person_id: "dad", points: 40, note: "Served coffee", by_account: staff)
    kudos.award!(pco_person_id: "emma", points: 50, note: "Brought a friend", by_account: staff)

    get "/api/v1/my_points", headers: auth_headers(account)

    expect(response).to have_http_status(:ok)
    people = json["people"]
    expect(people.map { |p| [p["relation"], p["first_name"], p["balance"]] })
      .to eq([["you", "Mark", 40], ["child", "Emma", 50], ["child", "Noah", 0]])
    expect(people[1]["history"].first).to include("points" => 50, "note" => "Brought a friend")
  end

  it "never includes another family's kids" do
    other = create(:spirely_family, church: church, pco_person_id: "other")
    create(:spirely_child, family: other, first_name: "Liam", pco_person_id: "liam")
    kudos.award!(pco_person_id: "liam", points: 10, note: "x", by_account: staff)

    get "/api/v1/my_points", headers: auth_headers(account)

    expect(json["people"].map { |p| p["first_name"] }).not_to include("Liam")
  end

  it "works for an adult with no family record, matched by email" do
    create(:spirely_person, church: church, first_name: "Grace", email: "grace@example.com", pco_person_id: "grace")
    get "/api/v1/my_points", headers: auth_headers(create(:account, email: "grace@example.com"))
    expect(json["people"].map { |p| p["relation"] }).to eq(["you"])
  end

  describe "claiming a promo code" do
    before { church.promo_codes.create!(code: "BRING-A-FRIEND", label: "Brought a friend", points: 30) }

    it "claims for yourself or one of your kids, and answers with fresh balances" do
      post "/api/v1/my_points/claim", params: { code: "bring-a-friend", key: "child-#{emma.id}" },
           headers: auth_headers(account), as: :json

      expect(response).to have_http_status(:created)
      expect(json["claimed"]).to include("points" => 30, "note" => "Brought a friend")
      expect(json["people"].find { |p| p["first_name"] == "Emma" }["balance"]).to eq(30)

      post "/api/v1/my_points/claim", params: { code: "bring-a-friend", key: "dad" }, headers: auth_headers(account), as: :json
      expect(json["people"].first["balance"]).to eq(30)
    end

    it "says so when they've already used it" do
      2.times do
        post "/api/v1/my_points/claim", params: { code: "BRING-A-FRIEND", key: "dad" }, headers: auth_headers(account), as: :json
      end
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to match(/already used/)
    end

    it "won't claim for another family's kid or a kid not in Planning Center" do
      other = create(:spirely_family, church: church, pco_person_id: "other")
      liam = create(:spirely_child, family: other, first_name: "Liam", pco_person_id: "liam")

      post "/api/v1/my_points/claim", params: { code: "BRING-A-FRIEND", key: "child-#{liam.id}" },
           headers: auth_headers(account), as: :json
      expect(response).to have_http_status(:not_found)

      post "/api/v1/my_points/claim", params: { code: "BRING-A-FRIEND", key: "child-#{noah.id}" },
           headers: auth_headers(account), as: :json
      expect(response).to have_http_status(:not_found)
      expect(church.points_entries.count).to eq(0)
    end
  end

  it "404s when Kudos is off" do
    church.update!(enabled_modules: [])
    get "/api/v1/my_points", headers: auth_headers(account)
    expect(response).to have_http_status(:not_found)
  end

  describe "the store" do
    let(:shirt) { church.store_items.create!(name: "T-shirt", points: 30, stock: 2) }
    let(:kids_prize) { church.store_items.create!(name: "Prize box", points: 20, audience: "kids") }
    let(:coffee) { church.store_items.create!(name: "Coffee", points: 10, kind: "code", instructions: "Show at the café.") }

    before do
      kudos.award!(pco_person_id: "emma", points: 50, note: "Brought a friend", by_account: staff)
      Spirely::KudosStore.new(church).add_codes!(coffee, "CAFE-1")
      shirt && kids_prize
    end

    it "shows what each person can get" do
      get "/api/v1/my_points/store", params: { key: "child-#{emma.id}" }, headers: auth_headers(account)
      expect(json["balance"]).to eq(50)
      expect(json["items"].map { |i| i["name"] }).to eq(["Coffee", "T-shirt", "Prize box"])
      expect(json["items"].first).not_to have_key("instructions")

      get "/api/v1/my_points/store", params: { key: "dad" }, headers: auth_headers(account)
      expect(json["items"].map { |i| i["name"] }).to eq(%w[Coffee T-shirt])
    end

    it "redeems for a kid, and shows the order and any code in their history" do
      post "/api/v1/my_points/redeem", params: { key: "child-#{emma.id}", item_id: coffee.id }, headers: auth_headers(account), as: :json

      expect(response).to have_http_status(:created)
      expect(json["redeemed"]["order"]).to include("status" => "fulfilled", "codes" => ["CAFE-1"],
                                                    "instructions" => "Show at the café.")
      kid = json["people"].find { |p| p["first_name"] == "Emma" }
      expect(kid["balance"]).to eq(40)
      expect(kid["orders"].first).to include("codes" => ["CAFE-1"])

      coffee.update!(per_person_limit: 1)
      get "/api/v1/my_points/store", params: { key: "child-#{emma.id}" }, headers: auth_headers(account)
      expect(json["items"].find { |i| i["name"] == "Coffee" }).to include("limit_left" => 0)
      expect(json["items"].find { |i| i["name"] == "T-shirt" }).to include("limit_left" => nil)
    end

    it "says why when they can't afford it" do
      post "/api/v1/my_points/redeem", params: { key: "dad", item_id: shirt.id }, headers: auth_headers(account), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to eq("Mark has 0 points — that's 30.")
    end

    it "won't spend another family's kid's points" do
      other = create(:spirely_family, church: church, pco_person_id: "other")
      liam = create(:spirely_child, family: other, first_name: "Liam", pco_person_id: "liam")
      kudos.award!(pco_person_id: "liam", points: 100, note: "x", by_account: staff)

      post "/api/v1/my_points/redeem", params: { key: "child-#{liam.id}", item_id: shirt.id }, headers: auth_headers(account), as: :json

      expect(response).to have_http_status(:not_found)
      expect(church.store_orders).to be_empty
    end
  end

  it "lets a parent keep a kid off the leaderboards" do
    patch "/api/v1/my_points/leaderboard", params: { key: "child-#{emma.id}", opt_out: true }, headers: auth_headers(account), as: :json
    expect(response).to have_http_status(:ok)
    expect(json["people"].find { |p| p["first_name"] == "Emma" }["leaderboard_opt_out"]).to be(true)
    expect(church.people.find_by!(pco_person_id: "emma").kudos_leaderboard_opt_out).to be(true)
  end
end
