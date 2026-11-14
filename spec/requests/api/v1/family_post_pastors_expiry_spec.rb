require "rails_helper"

# 5ST-79 follow-up: "Pastors only" prayer requests, the Pastor flag, and
# prayer requests that expire after 30 days unless renewed.
RSpec.describe "Pastors only and prayer request expiry", type: :request do
  let(:church)  { create(:church) }
  let(:account) { create(:account) }
  let!(:family) { create(:spirely_family, church: church, account: account) }
  let(:other_account) { create(:account) }
  let!(:other_family) { create(:spirely_family, church: church, account: other_account) }

  let(:admin) { create(:account).tap { |a| create(:membership, :admin, church: church, account: a) } }
  let(:pastor_admin) { create(:account).tap { |a| create(:membership, :admin, church: church, account: a, pastor: true) } }
  let(:pastor) do
    create(:account, first_name: "Dan", last_name: "Reed", email: "dan@example.com")
      .tap { |a| create(:membership, church: church, account: a, pastor: true) }
  end

  def json = JSON.parse(response.body)
  def ids = json["family_posts"].map { |p| p["id"] }

  def prayer(family_ = family, **attrs)
    create(:spirely_family_post, church: church, family: family_, post_type: "prayer_request", status: "approved", **attrs)
  end

  before { use_tenant_host!(church) }

  describe "a family sharing pastors only" do
    it "posts straight away, even when the church reviews posts" do
      church.update!(family_posts_moderation_enabled: true)
      post "/api/v1/family_posts",
           params: { family_post: { post_type: "prayer_request", audience: "pastors_only", body: "Please pray for our marriage." } },
           headers: auth_headers(account)

      expect(response).to have_http_status(:created)
      expect(json).to include("audience" => "pastors_only", "status" => "approved")
    end

    it "doesn't show it to other families" do
      shared = prayer(audience: "pastors_only")
      get "/api/v1/family_posts", headers: auth_headers(other_account)
      expect(ids).not_to include(shared.id)
    end
  end

  describe "staff's view" do
    let!(:shared) { prayer(audience: "pastors_only") }
    let!(:staff_only) { prayer(audience: "staff_only") }
    let!(:everyone) { prayer }

    it "hides pastors-only requests from admins who aren't pastors" do
      get "/api/v1/admin/family_posts", headers: auth_headers(admin)
      expect(ids).to contain_exactly(staff_only.id, everyone.id)

      get "/api/v1/admin/family_posts/#{shared.id}", headers: auth_headers(admin)
      expect(response).to have_http_status(:not_found)
      post "/api/v1/admin/family_posts/#{shared.id}/prayer", headers: auth_headers(admin)
      expect(response).to have_http_status(:not_found)
    end

    it "shows them to an admin who's a pastor" do
      get "/api/v1/admin/family_posts", params: { audience: "pastors_only" }, headers: auth_headers(pastor_admin)
      expect(ids).to eq([shared.id])
    end

    it "lets a pastor who isn't an admin read and pray for prayer and praise, and nothing more" do
      milestone = create(:spirely_family_post, church: church, family: family, post_type: "milestone", status: "approved")
      pending   = prayer(status: "pending")

      get "/api/v1/admin/family_posts", params: { post_type: "prayer_request,praise_report" }, headers: auth_headers(pastor)
      expect(response).to have_http_status(:ok)
      expect(ids).to contain_exactly(shared.id, staff_only.id, everyone.id)

      get "/api/v1/admin/family_posts", headers: auth_headers(pastor)
      expect(ids).not_to include(milestone.id, pending.id)

      post "/api/v1/admin/family_posts/#{shared.id}/prayer", headers: auth_headers(pastor)
      expect(json).to include("praying" => true, "prayer_count" => 1)

      post "/api/v1/admin/family_posts/#{pending.id}/approve", headers: auth_headers(pastor)
      expect(response).to have_http_status(:forbidden)
      delete "/api/v1/admin/family_posts/#{everyone.id}", headers: auth_headers(pastor)
      expect(response).to have_http_status(:forbidden)
    end

    it "is still closed to members who aren't admins or pastors" do
      get "/api/v1/admin/family_posts", headers: auth_headers(account)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "expiry" do
    let!(:old) { prayer(created_at: 31.days.ago) }

    it "takes another family's expired request off the feed, but the poster still sees theirs" do
      get "/api/v1/family_posts", headers: auth_headers(other_account)
      expect(ids).not_to include(old.id)

      get "/api/v1/family_posts", headers: auth_headers(account)
      mine = json["family_posts"].find { |p| p["id"] == old.id }
      expect(mine).to include("expired" => true)
      expect(Time.zone.parse(mine["expires_at"])).to be_within(1.second).of(old.created_at + 30.days)
    end

    it "lets the poster keep praying, which shares it for 30 more days" do
      post "/api/v1/family_posts/#{old.id}/renew", headers: auth_headers(account)
      expect(response).to have_http_status(:ok)
      expect(json).to include("expired" => false)

      get "/api/v1/family_posts", headers: auth_headers(other_account)
      expect(ids).to include(old.id)
    end

    it "only renews the family's own requests" do
      post "/api/v1/family_posts/#{old.id}/renew", headers: auth_headers(other_account)
      expect(response).to have_http_status(:not_found)
    end

    it "keeps expired requests on staff's page, marked expired" do
      get "/api/v1/admin/family_posts", headers: auth_headers(admin)
      expect(json["family_posts"].find { |p| p["id"] == old.id }).to include("expired" => true)
    end
  end

  describe "the Pastor flag" do
    it "can be set on anyone, admins included, and lists them" do
      admin_membership = Membership.find_by(account: pastor_admin, church: church)
      member = create(:membership, church: church, account: create(:account, email: "amy@example.com"))

      patch "/api/v1/admin/staff/members/#{member.id}", params: { pastor: true }, headers: auth_headers(admin)
      expect(json).to include("pastor" => true)

      get "/api/v1/admin/staff", headers: auth_headers(admin)
      expect(json["pastors"].map { |p| p["id"] }).to contain_exactly(admin_membership.id, member.id)

      get "/api/v1/admin/staff/candidates", params: { q: Account.find(admin.id).email[0, 6], flag: "pastor" }, headers: auth_headers(admin)
      expect(json["members"].map { |m| m["email"] }).to include(Account.find(admin.id).email)
    end

    it "tells a pastor's home to link to the Prayer page" do
      get "/api/v1/me", headers: auth_headers(pastor)
      expect(json).to include("pastor" => true)
      get "/api/v1/me", headers: auth_headers(admin)
      expect(json).to include("pastor" => false)
    end
  end
end
