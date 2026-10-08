require "rails_helper"

RSpec.describe "/api/v1/admin/group_types", type: :request do
  def admin_for(church)
    account = create(:account)
    create(:membership, :admin, church: church, account: account)
    account
  end

  def group_type(church, name, pco_id)
    church.group_types.create!(name: name, pco_group_type_id: pco_id)
  end

  it "lists current group types with their audience and active group count" do
    church = create(:church, enabled_modules: ["smallgroups"])
    adults = group_type(church, "Adult Groups", "gt1")
    church.groups.create!(name: "Tuesday", pco_group_id: "g1", group_type: adults)
    church.groups.create!(name: "Archived", pco_group_id: "g2", group_type: adults, archived_at: 1.day.ago)
    church.group_types.create!(name: "Gone", pco_group_type_id: "gt9", removed_at: 1.day.ago)

    use_tenant_host!(church)
    get "/api/v1/admin/group_types", headers: auth_headers(admin_for(church))

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq([
      { "id" => adults.id, "name" => "Adult Groups", "color" => nil, "audience" => "adults", "groups_count" => 1 },
    ])
  end

  it "marks a group type as children's" do
    church = create(:church, enabled_modules: ["smallgroups"])
    kids = group_type(church, "Kids Groups", "gt2")

    use_tenant_host!(church)
    patch "/api/v1/admin/group_types/#{kids.id}", params: { audience: "children" },
          headers: auth_headers(admin_for(church)), as: :json

    expect(response).to have_http_status(:ok)
    expect(kids.reload.audience).to eq("children")
  end

  it "rejects an unknown audience" do
    church = create(:church, enabled_modules: ["smallgroups"])
    kids = group_type(church, "Kids Groups", "gt2")

    use_tenant_host!(church)
    patch "/api/v1/admin/group_types/#{kids.id}", params: { audience: "teens" },
          headers: auth_headers(admin_for(church)), as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(kids.reload.audience).to eq("adults")
  end

  it "404s when no groups module is on" do
    church = create(:church, enabled_modules: ["kidsmin"])

    use_tenant_host!(church)
    get "/api/v1/admin/group_types", headers: auth_headers(admin_for(church))

    expect(response).to have_http_status(:not_found)
    expect(JSON.parse(response.body)["code"]).to eq("module_disabled")
  end
end
