require "rails_helper"

RSpec.describe "Admin config API — branding", type: :request do
  def admin_for(church)
    account = create(:account)
    create(:membership, :admin, church: church, account: account)
    account
  end

  describe "GET /api/v1/admin/config" do
    it "returns display_name and logo_url" do
      church = create(:church, display_name: "Kids Nook")
      admin  = admin_for(church)

      use_tenant_host!(church)
      get "/api/v1/admin/config", headers: auth_headers(admin)

      body = JSON.parse(response.body)
      expect(body["display_name"]).to eq("Kids Nook")
      expect(body["logo_url"]).to be_nil
    end
  end

  describe "PATCH /api/v1/admin/config" do
    it "saves a new display_name" do
      church = create(:church)
      admin  = admin_for(church)

      use_tenant_host!(church)
      patch "/api/v1/admin/config", params: { config: { display_name: "Kids Nook" } }, headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(church.reload.display_name).to eq("Kids Nook")
      expect(JSON.parse(response.body)["display_name"]).to eq("Kids Nook")
    end

    it "clears display_name when an empty string is sent on purpose" do
      church = create(:church, display_name: "Kids Nook")
      admin  = admin_for(church)

      use_tenant_host!(church)
      patch "/api/v1/admin/config", params: { config: { display_name: "" } }, headers: auth_headers(admin)

      expect(church.reload.display_name).to eq("")
      expect(church.brand_name).to eq(church.name)
    end

    it "leaves display_name untouched when the field isn't sent at all" do
      church = create(:church, display_name: "Kids Nook")
      admin  = admin_for(church)

      use_tenant_host!(church)
      patch "/api/v1/admin/config", params: { config: { public_site_theme: "v2" } }, headers: auth_headers(admin)

      expect(church.reload.display_name).to eq("Kids Nook")
    end

    it "attaches a logo and returns its URL" do
      church = create(:church)
      admin  = admin_for(church)
      file = Rack::Test::UploadedFile.new(StringIO.new("x" * 100), "image/png", original_filename: "logo.png")

      use_tenant_host!(church)
      patch "/api/v1/admin/config", params: { config: { logo: file } }, headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(church.reload.logo).to be_attached
      expect(JSON.parse(response.body)["logo_url"]).to be_present
    end

    it "rejects a disallowed logo content type and doesn't attach it" do
      church = create(:church)
      admin  = admin_for(church)
      file = Rack::Test::UploadedFile.new(StringIO.new("x" * 100), "application/pdf", original_filename: "logo.pdf")

      use_tenant_host!(church)
      patch "/api/v1/admin/config", params: { config: { logo: file } }, headers: auth_headers(admin)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(church.reload.logo).not_to be_attached
    end
  end

  describe "DELETE /api/v1/admin/config/logo" do
    it "removes an attached logo" do
      church = create(:church)
      church.logo.attach(io: StringIO.new("x" * 100), filename: "logo.png", content_type: "image/png")
      admin = admin_for(church)

      use_tenant_host!(church)
      delete "/api/v1/admin/config/logo", headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["logo_url"]).to be_nil
      expect(church.reload.logo).not_to be_attached
    end

    it "is a no-op when no logo is attached" do
      church = create(:church)
      admin  = admin_for(church)

      use_tenant_host!(church)
      delete "/api/v1/admin/config/logo", headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
    end
  end
end
