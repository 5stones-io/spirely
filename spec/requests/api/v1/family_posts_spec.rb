require "rails_helper"

RSpec.describe "Family Posts API", type: :request do
  describe "GET /api/v1/family_posts" do
    it "requires a family" do
      church = create(:church)
      staff  = create(:account)
      create(:membership, :admin, church: church, account: staff)

      use_tenant_host!(church)
      get "/api/v1/family_posts", headers: auth_headers(staff)
      expect(response).to have_http_status(:not_found)
    end

    it "shows approved church-audience posts from any family, plus this family's own posts of any status/audience" do
      church  = create(:church)
      account = create(:account)
      family  = create(:spirely_family, church: church, account: account)
      other_family = create(:spirely_family, church: church)

      visible_from_other = create(:spirely_family_post, church: church, family: other_family, status: "approved", audience: "church")
      create(:spirely_family_post, church: church, family: other_family, status: "pending", audience: "church")
      create(:spirely_family_post, church: church, family: other_family, status: "approved", audience: "staff_only")

      own_pending    = create(:spirely_family_post, church: church, family: family, status: "pending", audience: "church")
      own_staff_only = create(:spirely_family_post, church: church, family: family, status: "approved", audience: "staff_only")

      use_tenant_host!(church)
      get "/api/v1/family_posts", headers: auth_headers(account)
      expect(response).to have_http_status(:ok)

      ids = JSON.parse(response.body)["family_posts"].map { |p| p["id"] }
      expect(ids).to contain_exactly(visible_from_other.id, own_pending.id, own_staff_only.id)
    end

    it "never shows another family's staff_only or unapproved posts" do
      church  = create(:church)
      account = create(:account)
      family  = create(:spirely_family, church: church, account: account)
      other_family = create(:spirely_family, church: church)
      hidden = create(:spirely_family_post, church: church, family: other_family, status: "approved", audience: "staff_only")

      use_tenant_host!(church)
      get "/api/v1/family_posts", headers: auth_headers(account)
      ids = JSON.parse(response.body)["family_posts"].map { |p| p["id"] }
      expect(ids).not_to include(hidden.id)
    end
  end

  describe "POST /api/v1/family_posts" do
    it "creates a post attributed to the current family, auto-approved when moderation is off" do
      church  = create(:church, family_posts_moderation_enabled: false)
      account = create(:account)
      family  = create(:spirely_family, church: church, account: account)

      use_tenant_host!(church)
      post "/api/v1/family_posts",
           params: { family_post: { post_type: "praise_report", body: "Grateful for a healthy checkup!" } },
           headers: auth_headers(account)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("approved")
      expect(body["family_id"]).to eq(family.id)
    end

    it "starts pending when the church has moderation enabled" do
      church  = create(:church, family_posts_moderation_enabled: true)
      account = create(:account)
      create(:spirely_family, church: church, account: account)

      use_tenant_host!(church)
      post "/api/v1/family_posts", params: { family_post: { body: "Please pray for our family." } }, headers: auth_headers(account)
      expect(JSON.parse(response.body)["status"]).to eq("pending")
    end

    it "requires a body" do
      church  = create(:church)
      account = create(:account)
      create(:spirely_family, church: church, account: account)

      use_tenant_host!(church)
      post "/api/v1/family_posts", params: { family_post: { body: "" } }, headers: auth_headers(account)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects attributing the post to another family's child" do
      church  = create(:church)
      account = create(:account)
      create(:spirely_family, church: church, account: account)
      unrelated_child = create(:spirely_child)

      use_tenant_host!(church)
      post "/api/v1/family_posts",
           params: { family_post: { body: "Milestone!", child_id: unrelated_child.id } },
           headers: auth_headers(account)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "stamps the signed-in guardian when a second-account guardian posts" do
      church   = create(:church)
      family   = create(:spirely_family, church: church)
      g_account = create(:account)
      guardian = create(:spirely_guardian, family: family, church: church, account: g_account, first_name: "Pat")

      use_tenant_host!(church)
      post "/api/v1/family_posts", params: { family_post: { body: "So proud of our kids." } }, headers: auth_headers(g_account)
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["author_name"]).to include("Pat")
      expect(Spirely::FamilyPost.last.guardian_id).to eq(guardian.id)
    end
  end

  describe "PATCH /api/v1/family_posts/:id" do
    it "allows editing a still-pending post" do
      church  = create(:church, family_posts_moderation_enabled: true)
      account = create(:account)
      family  = create(:spirely_family, church: church, account: account)
      post_record = create(:spirely_family_post, church: church, family: family, status: "pending")

      use_tenant_host!(church)
      patch "/api/v1/family_posts/#{post_record.id}", params: { family_post: { body: "Updated request" } }, headers: auth_headers(account)
      expect(response).to have_http_status(:ok)
      expect(post_record.reload.body).to eq("Updated request")
    end

    it "refuses to edit a post that's already been moderated" do
      church  = create(:church)
      account = create(:account)
      family  = create(:spirely_family, church: church, account: account)
      admin   = create(:account)
      membership = create(:membership, :admin, church: church, account: admin)
      post_record = create(:spirely_family_post, church: church, family: family, status: "pending")
      post_record.approve!(membership)

      use_tenant_host!(church)
      patch "/api/v1/family_posts/#{post_record.id}", params: { family_post: { body: "Trying to sneak an edit in" } }, headers: auth_headers(account)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["code"]).to eq("already_moderated")
    end

    it "404s for another family's post" do
      church  = create(:church)
      account = create(:account)
      create(:spirely_family, church: church, account: account)
      other_post = create(:spirely_family_post, church: church)

      use_tenant_host!(church)
      patch "/api/v1/family_posts/#{other_post.id}", params: { family_post: { body: "nope" } }, headers: auth_headers(account)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/family_posts/:id" do
    it "destroys the family's own post" do
      church  = create(:church)
      account = create(:account)
      family  = create(:spirely_family, church: church, account: account)
      post_record = create(:spirely_family_post, church: church, family: family)

      use_tenant_host!(church)
      delete "/api/v1/family_posts/#{post_record.id}", headers: auth_headers(account)
      expect(response).to have_http_status(:no_content)
      expect(Spirely::FamilyPost.exists?(post_record.id)).to eq(false)
    end

    it "404s for another family's post" do
      church  = create(:church)
      account = create(:account)
      create(:spirely_family, church: church, account: account)
      other_post = create(:spirely_family_post, church: church)

      use_tenant_host!(church)
      delete "/api/v1/family_posts/#{other_post.id}", headers: auth_headers(account)
      expect(response).to have_http_status(:not_found)
    end
  end
end
