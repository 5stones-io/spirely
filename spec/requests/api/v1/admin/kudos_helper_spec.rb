require "rails_helper"

# Kudos helpers: members who run the store desk (checkout and the pickup
# queue) without being admins.
RSpec.describe "Kudos helpers", type: :request do
  let(:church) { create(:church, enabled_modules: ["kudos"]) }
  let(:admin)  { create(:account).tap { |a| create(:membership, :admin, church: church, account: a) } }
  let!(:helper) do
    create(:account, first_name: "Lee", last_name: "Smith", email: "lee@example.com")
      .tap { |a| create(:membership, church: church, account: a, kudos_helper: true) }
  end
  let!(:sarah) { create(:spirely_person, church: church, first_name: "Sarah", last_name: "Mitchell", pco_person_id: "p1") }
  let!(:shirt) { church.store_items.create!(name: "T-shirt", points: 100, stock: 5) }

  before do
    use_tenant_host!(church)
    kudos.award!(pco_person_id: "p1", points: 500, note: "Thanks", by_account: admin)
  end

  def json = JSON.parse(response.body)
  def kudos = Spirely::Kudos.new(church)
  def store = Spirely::KudosStore.new(church)

  it "finds someone, checks them out and hands over waiting orders" do
    get "/api/v1/admin/kudos/people", params: { q: "sarah" }, headers: auth_headers(helper)
    expect(json["people"]).to match([a_hash_including("pco_person_id" => "p1", "balance" => 500)])

    get "/api/v1/admin/kudos/store/items", headers: auth_headers(helper)
    expect(json["items"].map { |i| i["id"] }).to eq([shirt.id])

    post "/api/v1/admin/kudos/store/checkout", params: { pco_person_id: "p1", lines: [{ item_id: shirt.id, quantity: 1 }] },
         headers: auth_headers(helper), as: :json
    expect(response).to have_http_status(:created)
    expect(json["balance"]).to eq(400)

    order = store.redeem!(pco_person_id: "p1", item_id: shirt.id)
    get "/api/v1/admin/kudos/store/orders", params: { status: "all" }, headers: auth_headers(helper)
    expect(json["orders"].map { |o| o["id"] }).to eq([order.id]) # the queue only, not every order

    post "/api/v1/admin/kudos/store/orders/#{order.id}/fulfill", headers: auth_headers(helper)
    expect(json).to include("status" => "fulfilled", "fulfilled_by" => "Lee Smith")
  end

  it "cancels a waiting order, giving the points back" do
    order = store.redeem!(pco_person_id: "p1", item_id: shirt.id)
    post "/api/v1/admin/kudos/store/orders/#{order.id}/cancel", headers: auth_headers(helper)
    expect(json).to include("status" => "cancelled", "cancelled_by" => "Lee Smith")
    expect(kudos.totals(sarah)[:balance]).to eq(500)
  end

  it "can't edit the store, award points or see the people list" do
    requests = [
      -> { patch "/api/v1/admin/kudos/store/items/#{shirt.id}", params: { points: 1 }, headers: auth_headers(helper), as: :json },
      -> { post "/api/v1/admin/kudos/entries", params: { pco_person_id: "p1", points: 10 }, headers: auth_headers(helper), as: :json },
      -> { get "/api/v1/admin/kudos/people", headers: auth_headers(helper) },
      -> { get "/api/v1/admin/kudos/people/p1", headers: auth_headers(helper) },
      -> { get "/api/v1/admin/kudos", headers: auth_headers(helper) },
    ]
    requests.each do |req|
      req.call
      expect(response).to have_http_status(:forbidden)
    end
  end

  it "keeps everyone else out of the store desk" do
    member = create(:account).tap { |a| create(:membership, church: church, account: a) }
    get "/api/v1/admin/kudos/people", params: { q: "sarah" }, headers: auth_headers(member)
    expect(response).to have_http_status(:forbidden)
    post "/api/v1/admin/kudos/store/checkout", params: { pco_person_id: "p1", lines: [{ item_id: shirt.id, quantity: 1 }] },
         headers: auth_headers(member), as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it "tells a helper's home it can link to the store desk, while Kudos is on" do
    get "/api/v1/me", headers: auth_headers(helper)
    expect(json["store_desk"]).to be(true)

    church.update!(enabled_modules: [])
    get "/api/v1/me", headers: auth_headers(helper)
    expect(json["store_desk"]).to be(false)
  end

  it "lets admins mark helpers from Settings → Kudos" do
    other = create(:account, first_name: "Ana", last_name: "Diaz", email: "ana@example.com")
    member = create(:membership, church: church, account: other)

    get "/api/v1/admin/staff/candidates", params: { q: "ana", flag: "kudos_helper" }, headers: auth_headers(admin)
    expect(json["members"].map { |m| m["id"] }).to eq([member.id])

    patch "/api/v1/admin/staff/members/#{member.id}", params: { kudos_helper: true }, headers: auth_headers(admin), as: :json
    expect(json).to include("kudos_helper" => true, "staff" => false)

    get "/api/v1/admin/staff", headers: auth_headers(admin)
    expect(json["kudos_helpers"].map { |m| m["email"] }).to contain_exactly("ana@example.com", helper.email)
    expect(json["time_card_staff"]).to eq([])

    get "/api/v1/admin/staff/candidates", params: { q: "ana", flag: "kudos_helper" }, headers: auth_headers(admin)
    expect(json["members"]).to eq([])

    patch "/api/v1/admin/staff/members/#{member.id}", params: {}, headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:bad_request)
  end
end
