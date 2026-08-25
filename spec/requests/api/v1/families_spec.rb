require "rails_helper"

RSpec.describe "Family API", type: :request do
  describe "GET /api/v1/family" do
    it "returns 404 without a tenant host" do
      get "/api/v1/family"
      expect(response).to have_http_status(:not_found)
    end

    it "returns 401 without a token" do
      use_tenant_host!(create(:church))
      get "/api/v1/family"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns the current family with children" do
      church  = create(:church)
      account = create(:account)
      family  = create(:spirely_family, church: church, account: account)
      create(:spirely_child, family: family)

      use_tenant_host!(church)
      get "/api/v1/family", headers: auth_headers(account)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["family_name"]).to eq(family.family_name)
      expect(body["children"].size).to eq(1)
    end
  end

  describe "PATCH /api/v1/family" do
    it "updates permitted attributes" do
      church  = create(:church)
      account = create(:account)
      family  = create(:spirely_family, church: church, account: account)

      use_tenant_host!(church)
      patch "/api/v1/family", params: { family: { family_name: "New Name" } },
                               headers: auth_headers(account)
      expect(response).to have_http_status(:ok)
      expect(family.reload.family_name).to eq("New Name")
    end

    it "rejects an invalid email" do
      church  = create(:church)
      account = create(:account)
      create(:spirely_family, church: church, account: account)

      use_tenant_host!(church)
      patch "/api/v1/family", params: { family: { email: "not-an-email" } },
                               headers: auth_headers(account)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
