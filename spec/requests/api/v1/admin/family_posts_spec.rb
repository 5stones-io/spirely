require "rails_helper"

RSpec.describe "Admin Family Posts API", type: :request do
  describe "GET /api/v1/admin/family_posts" do
    it "requires admin" do
      church  = create(:church)
      account = create(:account)
      create(:membership, church: church, account: account, role: "family")

      use_tenant_host!(church)
      get "/api/v1/admin/family_posts", headers: auth_headers(account)
      expect(response).to have_http_status(:forbidden)
    end

    it "sees every post regardless of audience or status, scoped to this church" do
      church       = create(:church)
      other_church = create(:church)
      admin        = create(:account)
      create(:membership, :admin, church: church, account: admin)

      pending    = create(:spirely_family_post, church: church, status: "pending", audience: "church")
      staff_only = create(:spirely_family_post, church: church, status: "approved", audience: "staff_only")
      create(:spirely_family_post, church: other_church)

      use_tenant_host!(church)
      get "/api/v1/admin/family_posts", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)

      ids = JSON.parse(response.body)["family_posts"].map { |p| p["id"] }
      expect(ids).to contain_exactly(pending.id, staff_only.id)
    end

    it "filters by status" do
      church = create(:church)
      admin  = create(:account)
      create(:membership, :admin, church: church, account: admin)

      pending = create(:spirely_family_post, church: church, status: "pending")
      create(:spirely_family_post, church: church, status: "approved")

      use_tenant_host!(church)
      get "/api/v1/admin/family_posts", params: { status: "pending" }, headers: auth_headers(admin)
      ids = JSON.parse(response.body)["family_posts"].map { |p| p["id"] }
      expect(ids).to eq([pending.id])
    end
  end

  describe "POST /api/v1/admin/family_posts/:id/approve" do
    it "approves a pending post and stamps the moderating membership" do
      church     = create(:church)
      admin      = create(:account)
      membership = create(:membership, :admin, church: church, account: admin)
      post_record = create(:spirely_family_post, church: church, status: "pending")

      use_tenant_host!(church)
      post "/api/v1/admin/family_posts/#{post_record.id}/approve", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)

      post_record.reload
      expect(post_record.status).to eq("approved")
      expect(post_record.moderated_by_membership_id).to eq(membership.id)
    end
  end

  describe "POST /api/v1/admin/family_posts/:id/reject" do
    it "rejects a pending post with a reason" do
      church = create(:church)
      admin  = create(:account)
      create(:membership, :admin, church: church, account: admin)
      post_record = create(:spirely_family_post, church: church, status: "pending")

      use_tenant_host!(church)
      post "/api/v1/admin/family_posts/#{post_record.id}/reject",
           params: { reason: "Contains identifying details we ask families not to share publicly" },
           headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)

      post_record.reload
      expect(post_record.status).to eq("rejected")
      expect(post_record.rejected_reason).to eq("Contains identifying details we ask families not to share publicly")
    end
  end

  describe "DELETE /api/v1/admin/family_posts/:id" do
    it "removes a post outright" do
      church = create(:church)
      admin  = create(:account)
      create(:membership, :admin, church: church, account: admin)
      post_record = create(:spirely_family_post, church: church)

      use_tenant_host!(church)
      delete "/api/v1/admin/family_posts/#{post_record.id}", headers: auth_headers(admin)
      expect(response).to have_http_status(:no_content)
      expect(Spirely::FamilyPost.exists?(post_record.id)).to eq(false)
    end
  end
end
