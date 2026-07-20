require "rails_helper"

RSpec.describe "Family API", type: :request do
  describe "GET /api/v1/family" do
    it "returns 401 without a token" do
      get "/api/v1/family"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns the current family with children" do
      account = create(:account)
      family  = create(:spirely_family, account: account)
      create(:spirely_child, family: family)

      get "/api/v1/family", headers: auth_headers(account)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["family_name"]).to eq(family.family_name)
      expect(body["children"].size).to eq(1)
    end
  end

  describe "PATCH /api/v1/family" do
    it "updates permitted attributes" do
      account = create(:account)
      family  = create(:spirely_family, account: account)

      patch "/api/v1/family", params: { family: { family_name: "New Name" } },
                               headers: auth_headers(account)
      expect(response).to have_http_status(:ok)
      expect(family.reload.family_name).to eq("New Name")
    end

    it "rejects an invalid email" do
      account = create(:account)
      create(:spirely_family, account: account)

      patch "/api/v1/family", params: { family: { email: "not-an-email" } },
                               headers: auth_headers(account)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
