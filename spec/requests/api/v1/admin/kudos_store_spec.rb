require "rails_helper"

# Staff side of the Kudos store (5ST-63).
RSpec.describe "/api/v1/admin/kudos/store", type: :request do
  let(:church) { create(:church, enabled_modules: ["kudos"]) }
  let(:admin)  { create(:account, first_name: "Jenna", last_name: "Park").tap { |a| create(:membership, :admin, church: church, account: a) } }
  let!(:sarah) { create(:spirely_person, church: church, first_name: "Sarah", last_name: "Mitchell", pco_person_id: "p1") }

  before { use_tenant_host!(church) }

  def json = JSON.parse(response.body)
  def kudos = Spirely::Kudos.new(church)
  def store = Spirely::KudosStore.new(church)

  it "adds an item with an image under the church's own key prefix, then edits and hides it" do
    image = fixture_file_upload("store-item.png", "image/png")
    post "/api/v1/admin/kudos/store/items",
         params: { name: "Spirely T-shirt", description: "Youth sizes", points: 300, stock: 10, per_person_limit: 1,
                   audience: "everyone", image: image },
         headers: auth_headers(admin)

    expect(response).to have_http_status(:created)
    expect(json).to include("name" => "Spirely T-shirt", "points" => 300, "stock" => 10, "remaining" => 10,
                            "per_person_limit" => 1, "hidden" => false, "kind" => "physical")
    expect(json["image_url"]).to be_present
    item = church.store_items.sole
    expect(item.image.blob.key).to start_with("church-#{church.id}/kudos-store/")

    patch "/api/v1/admin/kudos/store/items/#{item.id}", params: { points: 250, hidden: true, stock: "" },
          headers: auth_headers(admin), as: :json
    expect(json).to include("points" => 250, "hidden" => true, "stock" => nil, "remaining" => nil)

    get "/api/v1/admin/kudos/store/items", headers: auth_headers(admin)
    expect(json["items"].map { |i| i["name"] }).to eq(["Spirely T-shirt"])
  end

  it "adds codes to a code item, and rejects a non-image upload" do
    post "/api/v1/admin/kudos/store/items",
         params: { name: "Café coffee", points: 50, kind: "code", instructions: "Show at the café.", codes: "A1\nB2\nA1" },
         headers: auth_headers(admin), as: :json
    expect(json).to include("kind" => "code", "remaining" => 2)

    id = json["id"]
    patch "/api/v1/admin/kudos/store/items/#{id}", params: { codes: "C3\nB2" }, headers: auth_headers(admin), as: :json
    expect(json["remaining"]).to eq(3)

    patch "/api/v1/admin/kudos/store/items/#{id}", params: { image: fixture_file_upload("store-item.png", "text/plain") },
          headers: auth_headers(admin)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(json["error"]).to eq("Pick a JPG, PNG, GIF or WebP image.")
  end

  it "lists the pickup queue oldest first, and hands over or cancels orders" do
    kudos.award!(pco_person_id: "p1", points: 1_000, note: "Thanks", by_account: admin)
    shirt = church.store_items.create!(name: "T-shirt", points: 100, stock: 5)
    first = store.redeem!(pco_person_id: "p1", item_id: shirt.id)
    second = store.redeem!(pco_person_id: "p1", item_id: shirt.id, quantity: 2)

    get "/api/v1/admin/kudos/store/orders", headers: auth_headers(admin)
    expect(json["pending_count"]).to eq(2)
    expect(json["orders"].map { |o| o["id"] }).to eq([first.id, second.id])
    expect(json["orders"].first["person"]).to include("name" => "Sarah Mitchell", "kid" => false)

    post "/api/v1/admin/kudos/store/orders/#{first.id}/fulfill", headers: auth_headers(admin)
    expect(json).to include("status" => "fulfilled", "fulfilled_by" => "Jenna Park")

    post "/api/v1/admin/kudos/store/orders/#{second.id}/cancel", headers: auth_headers(admin)
    expect(json).to include("status" => "cancelled", "cancelled_by" => "Jenna Park")
    expect(kudos.totals(sarah)[:balance]).to eq(900)

    post "/api/v1/admin/kudos/store/orders/#{second.id}/cancel", headers: auth_headers(admin)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "checks someone out, handing everything over" do
    kudos.award!(pco_person_id: "p1", points: 200, note: "Thanks", by_account: admin)
    shirt = church.store_items.create!(name: "T-shirt", points: 100)
    sticker = church.store_items.create!(name: "Sticker", points: 25)

    post "/api/v1/admin/kudos/store/checkout",
         params: { pco_person_id: "p1", lines: [{ item_id: shirt.id, quantity: 1 }, { item_id: sticker.id, quantity: 2 }] },
         headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:created)
    expect(json["balance"]).to eq(50)
    expect(json["orders"].map { |o| o["status"] }).to eq(%w[fulfilled fulfilled])
  end

  it "is admin-only" do
    member = create(:account).tap { |a| create(:membership, church: church, account: a) }
    get "/api/v1/admin/kudos/store/items", headers: auth_headers(member)
    expect(response).to have_http_status(:forbidden)
  end
end
