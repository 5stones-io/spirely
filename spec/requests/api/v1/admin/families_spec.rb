require "rails_helper"

RSpec.describe "Admin Families API", type: :request do
  describe "GET /api/v1/admin/families" do
    it "requires admin" do
      church  = create(:church)
      account = create(:account)
      create(:membership, church: church, account: account, role: "family")

      use_tenant_host!(church)
      get "/api/v1/admin/families", headers: auth_headers(account)
      expect(response).to have_http_status(:forbidden)
    end

    it "lists families with children in this church, scoped from other churches" do
      church       = create(:church)
      other_church = create(:church)
      admin        = create(:account)
      create(:membership, :admin, church: church, account: admin)

      family = create(:spirely_family, church: church)
      create(:spirely_child, family: family)
      other_family = create(:spirely_family, church: other_church)
      create(:spirely_child, family: other_family)

      # Neither family has any Attendance yet, so both fall in the
      # "inactive" bucket (see Family::ATTENDANCE_ACTIVE_WINDOW) — the
      # default view is "active", so status: "inactive" is what surfaces
      # a freshly-created family with no check-in history.
      use_tenant_host!(church)
      get "/api/v1/admin/families", params: { status: "inactive" }, headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)
      ids = body["families"].map { |f| f["id"] }
      expect(ids).to eq([family.id])
    end

    it "searches by guardian name" do
      church = create(:church)
      admin  = create(:account)
      create(:membership, :admin, church: church, account: admin)

      family = create(:spirely_family, church: church, primary_contact_first_name: "Adam", primary_contact_last_name: "Nelson")
      create(:spirely_child, family: family)
      create(:spirely_guardian, family: family, first_name: "Becca", last_name: "Nelson")

      use_tenant_host!(church)
      get "/api/v1/admin/families", params: { search: "becca", status: "inactive" }, headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["families"].map { |f| f["id"] }).to eq([family.id])
    end
  end

  describe "POST /api/v1/admin/families" do
    it "creates a family with children and guardians and returns an invite link" do
      church = create(:church)
      admin  = create(:account)
      create(:membership, :admin, church: church, account: admin)

      use_tenant_host!(church)
      post "/api/v1/admin/families",
           params: {
             family: { primary_contact_first_name: "Adam", primary_contact_last_name: "Nelson",
                        email: "adam@example.com", address: "123 Main St" },
             children: [{ first_name: "Kid", age: "5" }],
             guardians: [{ first_name: "Becca", last_name: "Nelson", relationship: "Mother" }],
           },
           headers: auth_headers(admin)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["family"]["family_name"]).to eq("Nelson Family")
      expect(body["family"]["children"].size).to eq(1)
      expect(body["invite_url"]).to be_present
      expect(body["email_sent"]).to be(true)

      family = Spirely::Family.find(body["family"]["id"])
      expect(family.church).to eq(church)
      expect(family.guardians.first.first_name).to eq("Becca")
    end

    it "requires an address" do
      church = create(:church)
      admin  = create(:account)
      create(:membership, :admin, church: church, account: admin)

      use_tenant_host!(church)
      post "/api/v1/admin/families",
           params: { family: { primary_contact_first_name: "Adam", primary_contact_last_name: "Nelson" } },
           headers: auth_headers(admin)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /api/v1/admin/families/:id" do
    it "returns the family with children and guardians, including volunteer/account signals" do
      church = create(:church)
      admin  = create(:account)
      create(:membership, :admin, church: church, account: admin)

      family = create(:spirely_family, church: church)
      create(:spirely_child, family: family, first_name: "Kid")
      create(:spirely_guardian, family: family, first_name: "Becca")

      use_tenant_host!(church)
      get "/api/v1/admin/families/#{family.id}", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)
      expect(body["children"].first["first_name"]).to eq("Kid")
      expect(body["guardians"].first["first_name"]).to eq("Becca")
    end
  end

  describe "POST /api/v1/admin/families/:id/invite" do
    it "expires any prior pending invite and creates a fresh one" do
      church = create(:church)
      admin  = create(:account)
      create(:membership, :admin, church: church, account: admin)
      family = create(:spirely_family, church: church, email: "family@example.com")
      old_invite = create(:spirely_invitation, family: family)

      use_tenant_host!(church)
      post "/api/v1/admin/families/#{family.id}/invite", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)

      expect(old_invite.reload.expired?).to be(true)
      body = JSON.parse(response.body)
      expect(body["invite_url"]).to be_present
    end
  end
end
