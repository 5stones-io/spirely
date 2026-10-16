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

  it "404s when Kudos is off" do
    church.update!(enabled_modules: [])
    get "/api/v1/my_points", headers: auth_headers(account)
    expect(response).to have_http_status(:not_found)
  end
end
