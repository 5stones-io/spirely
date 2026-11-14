require "rails_helper"

# Prayer requests and praise reports page (5ST-79).
RSpec.describe "Family post prayers API", type: :request do
  let(:church)  { create(:church) }
  let(:account) { create(:account) }
  let!(:family) { create(:spirely_family, church: church, account: account) }
  let(:other_family) { create(:spirely_family, church: church) }

  def json = JSON.parse(response.body)
  def photo = fixture_file_upload("store-item.png", "image/png")

  before { use_tenant_host!(church) }

  describe "POST /api/v1/family_posts/:id/prayer" do
    it "says this account is praying, and the count goes up" do
      post_ = create(:spirely_family_post, church: church, family: other_family, post_type: "prayer_request", status: "approved")

      post "/api/v1/family_posts/#{post_.id}/prayer", headers: auth_headers(account)
      expect(response).to have_http_status(:ok)
      expect(json).to include("praying" => true, "prayer_count" => 1)

      get "/api/v1/family_posts", headers: auth_headers(account)
      expect(json["family_posts"].first).to include("praying" => true, "prayer_count" => 1)
    end

    it "can't be used on a post this family can't see" do
      hidden = create(:spirely_family_post, church: church, family: other_family, post_type: "prayer_request",
                                            status: "approved", audience: "staff_only")
      post "/api/v1/family_posts/#{hidden.id}/prayer", headers: auth_headers(account)
      expect(response).to have_http_status(:not_found)
    end

    it "is only for prayer requests, and not your own" do
      praise = create(:spirely_family_post, church: church, family: other_family, post_type: "praise_report", status: "approved")
      own    = create(:spirely_family_post, church: church, family: family, post_type: "prayer_request", status: "approved")

      post "/api/v1/family_posts/#{praise.id}/prayer", headers: auth_headers(account)
      expect(response).to have_http_status(:unprocessable_entity)
      post "/api/v1/family_posts/#{own.id}/prayer", headers: auth_headers(account)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE /api/v1/family_posts/:id/prayer" do
    it "takes the prayer back off" do
      post_ = create(:spirely_family_post, church: church, family: other_family, post_type: "prayer_request", status: "approved")
      post_.pray!(account)

      delete "/api/v1/family_posts/#{post_.id}/prayer", headers: auth_headers(account)
      expect(response).to have_http_status(:ok)
      expect(json).to include("praying" => false, "prayer_count" => 0)
    end
  end

  describe "POST /api/v1/family_posts/:id/answer" do
    let!(:request_post) { create(:spirely_family_post, church: church, family: family, post_type: "prayer_request", status: "approved") }

    it "marks the family's own request answered" do
      post "/api/v1/family_posts/#{request_post.id}/answer",
           params: { answer: { note: "He's better!" } }, headers: auth_headers(account)

      expect(response).to have_http_status(:ok)
      expect(json["family_post"]).to include("answer_note" => "He's better!")
      expect(json["family_post"]["answered_at"]).to be_present
      expect(json["praise_report"]).to be_nil
    end

    it "shares a praise report with photos, which shows the request it answers" do
      post "/api/v1/family_posts/#{request_post.id}/answer",
           params: { answer: { note: "His fever broke!", share_as_praise: "true", photos: [photo] } },
           headers: auth_headers(account)

      expect(response).to have_http_status(:ok)
      praise = json["praise_report"]
      expect(praise).to include("post_type" => "praise_report", "body" => "His fever broke!")
      expect(praise["photos"].size).to eq(1)
      expect(praise["answers_post"]).to include("id" => request_post.id, "body" => request_post.body)
    end

    it "goes to review first when the church reviews posts" do
      church.update!(family_posts_moderation_enabled: true)
      post "/api/v1/family_posts/#{request_post.id}/answer",
           params: { answer: { note: "Thank you!", share_as_praise: "true" } }, headers: auth_headers(account)
      expect(json["praise_report"]).to include("status" => "pending")
    end

    it "is only for the family's own requests" do
      others = create(:spirely_family_post, church: church, family: other_family, post_type: "prayer_request", status: "approved")
      post "/api/v1/family_posts/#{others.id}/answer", params: { answer: { note: "x" } }, headers: auth_headers(account)
      expect(response).to have_http_status(:not_found)
    end

    it "explains when it can't be answered" do
      request_post.mark_answered!(note: nil)
      post "/api/v1/family_posts/#{request_post.id}/answer", params: { answer: { note: "x" } }, headers: auth_headers(account)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to be_present
    end
  end

  describe "GET /api/v1/family_posts" do
    it "takes several post types at once" do
      req    = create(:spirely_family_post, church: church, family: other_family, post_type: "prayer_request", status: "approved")
      praise = create(:spirely_family_post, church: church, family: other_family, post_type: "praise_report", status: "approved")
      create(:spirely_family_post, church: church, family: other_family, post_type: "milestone", status: "approved")

      get "/api/v1/family_posts", params: { post_type: "prayer_request,praise_report" }, headers: auth_headers(account)
      expect(json["family_posts"].map { |p| p["id"] }).to contain_exactly(req.id, praise.id)
    end
  end

  describe "staff" do
    let(:staff) { create(:account) }
    before { create(:membership, :admin, church: church, account: staff) }

    it "can pray for any request, staff-only ones too, and see the counts" do
      hidden = create(:spirely_family_post, church: church, family: other_family, post_type: "prayer_request",
                                            status: "approved", audience: "staff_only")
      hidden.pray!(account)

      post "/api/v1/admin/family_posts/#{hidden.id}/prayer", headers: auth_headers(staff)
      expect(json).to include("praying" => true, "prayer_count" => 2)

      get "/api/v1/admin/family_posts", params: { post_type: "prayer_request,praise_report" }, headers: auth_headers(staff)
      expect(json["family_posts"].first).to include("praying" => true, "prayer_count" => 2)

      delete "/api/v1/admin/family_posts/#{hidden.id}/prayer", headers: auth_headers(staff)
      expect(json).to include("praying" => false, "prayer_count" => 1)
    end

    it "isn't open to families" do
      req = create(:spirely_family_post, church: church, family: other_family, post_type: "prayer_request", status: "approved")
      post "/api/v1/admin/family_posts/#{req.id}/prayer", headers: auth_headers(account)
      expect(response).to have_http_status(:forbidden).or have_http_status(:not_found)
    end
  end
end
