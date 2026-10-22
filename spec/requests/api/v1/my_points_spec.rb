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
end
