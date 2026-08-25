require "rails_helper"

RSpec.describe "GET /api/v1/children", type: :request do
  it "returns 401 without a token" do
    use_tenant_host!(create(:church))
    get "/api/v1/children"
    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)["code"]).to eq("unauthorized")
  end

  it "returns 200 with a valid token" do
    church  = create(:church)
    account = create(:account)
    family  = create(:spirely_family, church: church, account: account)
    create(:spirely_child, family: family)

    use_tenant_host!(church)
    get "/api/v1/children", headers: auth_headers(account)
    expect(response).to have_http_status(:ok)
  end
end
