require "rails_helper"

RSpec.describe "Bridge::LoginController", type: :request do
  let(:hydra_admin) { Spirely.configuration.hydra_admin_url }

  describe "GET /bridge/login" do
    it "accepts immediately and redirects when Hydra reports skip: true" do
      stub_request(:get, "#{hydra_admin}/admin/oauth2/auth/requests/login")
        .with(query: { login_challenge: "chal-1" })
        .to_return(status: 200, body: { skip: true, subject: "42" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      stub_request(:put, "#{hydra_admin}/admin/oauth2/auth/requests/login/accept")
        .with(query: { login_challenge: "chal-1" })
        .to_return(status: 200, body: { redirect_to: "https://hydra.example/callback" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      get "/bridge/login", params: { login_challenge: "chal-1" }

      expect(response).to redirect_to("https://hydra.example/callback")
    end

    it "renders a login form when no existing login is remembered" do
      stub_request(:get, "#{hydra_admin}/admin/oauth2/auth/requests/login")
        .with(query: { login_challenge: "chal-2" })
        .to_return(status: 200, body: { skip: false }.to_json,
                   headers: { "Content-Type" => "application/json" })

      get "/bridge/login", params: { login_challenge: "chal-2" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("login-form")
      expect(response.body).to include("chal-2")
    end
  end

  describe "GET /bridge/login/callback" do
    it "rejects an invalid or expired key" do
      stub_request(:post, "http://www.example.com/auth/email-auth")
        .to_return(status: 422, body: { error: "invalid key" }.to_json)

      get "/bridge/login/callback", params: { key: "bad", email: "a@b.com", login_challenge: "chal-3" }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "accepts the Hydra login request once the key verifies" do
      account = create(:account, email: "verified@example.com")

      stub_request(:post, "http://www.example.com/auth/email-auth")
        .to_return(status: 200, body: { token: "jwt-here" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      stub_request(:put, "#{hydra_admin}/admin/oauth2/auth/requests/login/accept")
        .with(query: { login_challenge: "chal-3" })
        .to_return(status: 200, body: { redirect_to: "https://hydra.example/callback" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      get "/bridge/login/callback", params: { key: "good", email: account.email, login_challenge: "chal-3" }

      expect(response).to redirect_to("https://hydra.example/callback")
    end
  end
end
