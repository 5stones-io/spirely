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

    it "reports not_invited for a family with no Invitation row at all" do
      church = create(:church)
      admin  = create(:account)
      create(:membership, :admin, church: church, account: admin)
      family = create(:spirely_family, church: church, account: nil)
      create(:spirely_child, family: family)

      use_tenant_host!(church)
      get "/api/v1/admin/families", params: { status: "inactive" }, headers: auth_headers(admin)
      body = JSON.parse(response.body)["families"].first
      expect(body["account_linked"]).to eq(false)
      expect(body["invite_status"]).to eq("not_invited")
    end

    it "reports pending for a family with an active, unexpired invite" do
      church = create(:church)
      admin  = create(:account)
      create(:membership, :admin, church: church, account: admin)
      family = create(:spirely_family, church: church, account: nil)
      create(:spirely_child, family: family)
      create(:spirely_invitation, family: family, expires_at: 6.days.from_now)

      use_tenant_host!(church)
      get "/api/v1/admin/families", params: { status: "inactive" }, headers: auth_headers(admin)
      expect(JSON.parse(response.body)["families"].first["invite_status"]).to eq("pending")
    end

    it "reports expired for a family whose only invite has lapsed" do
      church = create(:church)
      admin  = create(:account)
      create(:membership, :admin, church: church, account: admin)
      family = create(:spirely_family, church: church, account: nil)
      create(:spirely_child, family: family)
      # expires_at is force-set to 7.days.from_now by Invitation's own
      # before_create callback regardless of what's passed at creation
      # (see generate_token) — update_column after the fact to actually
      # get an expired row.
      create(:spirely_invitation, family: family).update_column(:expires_at, 1.day.ago)

      use_tenant_host!(church)
      get "/api/v1/admin/families", params: { status: "inactive" }, headers: auth_headers(admin)
      expect(JSON.parse(response.body)["families"].first["invite_status"]).to eq("expired")
    end

    it "uses the most recent invite when a family has more than one" do
      church = create(:church)
      admin  = create(:account)
      create(:membership, :admin, church: church, account: admin)
      family = create(:spirely_family, church: church, account: nil)
      create(:spirely_child, family: family)
      create(:spirely_invitation, family: family, expires_at: 10.days.ago, created_at: 20.days.ago)
      create(:spirely_invitation, family: family, expires_at: 6.days.from_now, created_at: 1.day.ago)

      use_tenant_host!(church)
      get "/api/v1/admin/families", params: { status: "inactive" }, headers: auth_headers(admin)
      expect(JSON.parse(response.body)["families"].first["invite_status"]).to eq("pending")
    end

    it "omits invite_status once an account is linked" do
      church  = create(:church)
      admin   = create(:account)
      create(:membership, :admin, church: church, account: admin)
      linked  = create(:account)
      family  = create(:spirely_family, church: church, account: linked)
      create(:spirely_child, family: family)
      create(:spirely_invitation, family: family, expires_at: 6.days.from_now)

      use_tenant_host!(church)
      get "/api/v1/admin/families", params: { status: "inactive" }, headers: auth_headers(admin)
      body = JSON.parse(response.body)["families"].first
      expect(body["account_linked"]).to eq(true)
      expect(body["invite_status"]).to be_nil
    end

    it "reports last_check_in_at as the most recent attendance across the primary contact and every child" do
      church = create(:church)
      admin  = create(:account)
      create(:membership, :admin, church: church, account: admin)
      family = create(:spirely_family, church: church, pco_person_id: "parent-1")
      child  = create(:spirely_child, family: family, pco_person_id: "child-1")
      parent_person = create(:spirely_person, church: church, pco_person_id: "parent-1")
      child_person  = create(:spirely_person, church: church, pco_person_id: "child-1")
      create(:spirely_attendance, person: parent_person, checked_in_at: 10.days.ago)
      create(:spirely_attendance, person: child_person, checked_in_at: 2.days.ago)

      use_tenant_host!(church)
      get "/api/v1/admin/families", params: { status: "active" }, headers: auth_headers(admin)
      body = JSON.parse(response.body)["families"].first
      expect(Time.zone.parse(body["last_check_in_at"])).to be_within(1.minute).of(2.days.ago)
    end

    it "reports last_check_in_at as nil when nobody in the family has ever checked in" do
      church = create(:church)
      admin  = create(:account)
      create(:membership, :admin, church: church, account: admin)
      family = create(:spirely_family, church: church)
      create(:spirely_child, family: family)

      use_tenant_host!(church)
      get "/api/v1/admin/families", params: { status: "inactive" }, headers: auth_headers(admin)
      expect(JSON.parse(response.body)["families"].first["last_check_in_at"]).to be_nil
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
