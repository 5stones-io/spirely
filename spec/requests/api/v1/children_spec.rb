require "rails_helper"

RSpec.describe "GET /api/v1/children", type: :request do
  it "returns 401 without a token" do
    get "/api/v1/children"
    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)["code"]).to eq("unauthorized")
  end

  it "returns 200 with a valid token" do
    account = create(:account)
    family  = create(:spirely_family, account: account)
    create(:spirely_child, family: family)

    get "/api/v1/children", headers: auth_headers(account)
    expect(response).to have_http_status(:ok)
  end
end
