require "rails_helper"

RSpec.describe "Invitations API", type: :request do
  describe "GET /api/v1/invitations/:token" do
    it "returns 404 for an unknown token" do
      get "/api/v1/invitations/does-not-exist"
      expect(response).to have_http_status(:not_found)
    end

    it "returns the family preview for an active token" do
      invitation = create(:spirely_invitation)
      get "/api/v1/invitations/#{invitation.token}"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["family"]["email"]).to eq(invitation.family.email)
    end
  end

  describe "POST /api/v1/invitations/:token/accept" do
    it "returns 401 unauthenticated" do
      invitation = create(:spirely_invitation)
      post "/api/v1/invitations/#{invitation.token}/accept"
      expect(response).to have_http_status(:unauthorized)
    end

    it "links the account and marks the invitation accepted" do
      invitation = create(:spirely_invitation)
      account    = create(:account)

      post "/api/v1/invitations/#{invitation.token}/accept", headers: auth_headers(account)

      expect(response).to have_http_status(:ok)
      expect(invitation.reload.accepted?).to be(true)
      expect(invitation.family.reload.account_id).to eq(account.id)
    end
  end
end
