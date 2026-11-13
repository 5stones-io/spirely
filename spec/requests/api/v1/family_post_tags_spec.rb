require "rails_helper"

# A staff post that tags children, as families see it (5ST-78).
RSpec.describe "Tagged posts in the family feed", type: :request do
  let(:church) { create(:church, enabled_modules: ["kidsmin"]) }
  let(:staff)  { create(:membership, :admin, church: church, account: create(:account, first_name: "Maria", last_name: "Rivera")) }
  let(:emma_parent) { create(:account) }
  let(:noah_parent) { create(:account) }
  let(:other_parent) { create(:account) }
  let(:emma_family) { create(:spirely_family, church: church, account: emma_parent) }
  let(:noah_family) { create(:spirely_family, church: church, account: noah_parent) }
  let!(:other_family) { create(:spirely_family, church: church, account: other_parent) }
  let!(:emma) { create(:spirely_child, family: emma_family, first_name: "Emma") }
  let!(:noah) { create(:spirely_child, family: noah_family, first_name: "Noah") }
  let!(:tagged) do
    Spirely::FamilyPost.post_to_families!(church: church, author: staff, body: "Psalm 23 crafts!", child_ids: [emma.id, noah.id])
  end

  before { use_tenant_host!(church) }

  def json = JSON.parse(response.body)

  it "shows in a tagged family's feed, naming only that family's children" do
    get "/api/v1/family_posts", headers: auth_headers(emma_parent)

    post = json["family_posts"].sole
    expect(post).to include("id" => tagged.id, "staff_post" => true, "author_name" => "Maria Rivera", "mine" => false, "editable" => false)
    expect(post["tagged_children"]).to eq([{ "id" => emma.id, "first_name" => "Emma" }])

    get "/api/v1/family_posts/#{tagged.id}", headers: auth_headers(emma_parent)
    expect(response).to have_http_status(:ok)
  end

  it "doesn't show to a family none of whose children are tagged" do
    get "/api/v1/family_posts", headers: auth_headers(other_parent)
    expect(json["family_posts"]).to be_empty

    get "/api/v1/family_posts/#{tagged.id}", headers: auth_headers(other_parent)
    expect(response).to have_http_status(:not_found)
  end

  describe "DELETE /api/v1/family_posts/:id/tags" do
    it "takes this family's children off the post, so it leaves their feed only" do
      delete "/api/v1/family_posts/#{tagged.id}/tags", headers: auth_headers(emma_parent)
      expect(response).to have_http_status(:no_content)

      get "/api/v1/family_posts", headers: auth_headers(emma_parent)
      expect(json["family_posts"]).to be_empty
      get "/api/v1/family_posts", headers: auth_headers(noah_parent)
      expect(json["family_posts"].map { |p| p["id"] }).to eq([tagged.id])
    end

    it "can't be used on a post this family can't see" do
      delete "/api/v1/family_posts/#{tagged.id}/tags", headers: auth_headers(other_parent)
      expect(response).to have_http_status(:not_found)
      expect(tagged.reload.tagged_children.count).to eq(2)
    end
  end

  it "can't be edited or deleted by a tagged family" do
    patch "/api/v1/family_posts/#{tagged.id}", params: { family_post: { body: "Hacked" } }, headers: auth_headers(emma_parent)
    expect(response).to have_http_status(:not_found)
    delete "/api/v1/family_posts/#{tagged.id}", headers: auth_headers(emma_parent)
    expect(response).to have_http_status(:not_found)
  end
end
