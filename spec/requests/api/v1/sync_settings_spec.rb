require "rails_helper"

RSpec.describe "Sync settings API", type: :request do
  describe "GET /api/v1/sync_settings" do
    it "requires admin" do
      church  = create(:church)
      account = create(:account)
      create(:membership, church: church, account: account, role: "family")

      use_tenant_host!(church)
      get "/api/v1/sync_settings", headers: auth_headers(account)
      expect(response).to have_http_status(:forbidden)
    end

    it "returns settings for an admin" do
      church = create(:church)
      admin  = create(:account)
      create(:membership, :admin, church: church, account: admin)

      use_tenant_host!(church)
      get "/api/v1/sync_settings", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include("inbound_people_sync", "pco_ministry_tag")
      expect(JSON.parse(response.body)).not_to have_key("inbound_events_sync")
    end
  end

  describe "PATCH /api/v1/sync_settings" do
    it "updates the narrowed column set" do
      church = create(:church)
      admin  = create(:account)
      create(:membership, :admin, church: church, account: admin)

      use_tenant_host!(church)
      patch "/api/v1/sync_settings",
            params: { sync_setting: { pco_ministry_tag: "spirely", sync_frequency_hours: 12 } },
            headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["pco_ministry_tag"]).to eq("spirely")
      expect(body["sync_frequency_hours"]).to eq(12)
    end
  end
end
