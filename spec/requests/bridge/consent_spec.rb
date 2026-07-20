require "rails_helper"

RSpec.describe "Bridge::ConsentController", type: :request do
  let(:hydra_admin) { Spirely.configuration.hydra_admin_url }

  describe "GET /bridge/consent" do
    it "auto-accepts for a skip_consent (first-party) client" do
      stub_request(:get, "#{hydra_admin}/admin/oauth2/auth/requests/consent")
        .with(query: { consent_challenge: "chal-1" })
        .to_return(status: 200, body: { skip: true, requested_scope: ["profile"] }.to_json,
                   headers: { "Content-Type" => "application/json" })

      stub_request(:put, "#{hydra_admin}/admin/oauth2/auth/requests/consent/accept")
        .with(query: { consent_challenge: "chal-1" })
        .to_return(status: 200, body: { redirect_to: "https://churchcred.example/callback" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      get "/bridge/consent", params: { consent_challenge: "chal-1" }

      expect(response).to redirect_to("https://churchcred.example/callback")
    end

    it "renders a scope-listing consent screen for a non-trusted client" do
      stub_request(:get, "#{hydra_admin}/admin/oauth2/auth/requests/consent")
        .with(query: { consent_challenge: "chal-2" })
        .to_return(status: 200, body: {
          skip: false,
          requested_scope: %w[profile email],
          client: { client_id: "third-party-app", client_name: "Third Party App" }
        }.to_json, headers: { "Content-Type" => "application/json" })

      get "/bridge/consent", params: { consent_challenge: "chal-2" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Third Party App")
      expect(response.body).to include("profile")
      expect(response.body).to include("email")
    end
  end

  describe "POST /bridge/consent" do
    it "accepts the requested scopes and redirects" do
      stub_request(:put, "#{hydra_admin}/admin/oauth2/auth/requests/consent/accept")
        .with(query: { consent_challenge: "chal-3" })
        .to_return(status: 200, body: { redirect_to: "https://third-party.example/callback" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      post "/bridge/consent", params: { consent_challenge: "chal-3", grant_scope: ["profile"] }

      expect(response).to redirect_to("https://third-party.example/callback")
    end
  end
end
