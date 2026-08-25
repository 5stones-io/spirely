require "rails_helper"

RSpec.describe "GET /api/v1/me", type: :request do
  it "returns 401 without a token" do
    use_tenant_host!(create(:church))
    get "/api/v1/me"
    expect(response).to have_http_status(:unauthorized)
  end

  it "resolves staff for an admin membership" do
    church  = create(:church)
    account = create(:account)
    create(:membership, :admin, church: church, account: account)

    use_tenant_host!(church)
    get "/api/v1/me", headers: auth_headers(account)
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["role"]).to eq("staff")
  end

  it "resolves parent for a family membership with no admin access" do
    church  = create(:church)
    account = create(:account)
    create(:membership, church: church, account: account, role: "family")

    use_tenant_host!(church)
    get "/api/v1/me", headers: auth_headers(account)
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["role"]).to eq("parent")
  end

  it "resolves nil for an account with no membership at this church" do
    church  = create(:church)
    account = create(:account)

    use_tenant_host!(church)
    get "/api/v1/me", headers: auth_headers(account)
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["role"]).to be_nil
  end

  it "never exposes role_preview_enabled to a non-admin even when the church has it on" do
    church  = create(:church, role_preview_enabled: true)
    account = create(:account)
    create(:membership, church: church, account: account, role: "family")

    use_tenant_host!(church)
    get "/api/v1/me", headers: auth_headers(account)
    expect(JSON.parse(response.body)["role_preview_enabled"]).to be(false)
  end
end
