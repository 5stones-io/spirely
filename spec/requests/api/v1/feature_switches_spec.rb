require "rails_helper"

# Core feature switches (5ST-81): a church admin turns off features the
# church doesn't use. A feature that's off is hidden from everyone, so its
# endpoints answer 404 whoever asks.
RSpec.describe "Feature switches", type: :request do
  let(:church) { create(:church, enabled_modules: ["kidsmin"]) }
  let(:admin)  { create(:account) }
  let(:parent) { create(:account) }
  let!(:admin_membership) { create(:membership, :admin, church: church, account: admin) }
  let!(:family) { create(:spirely_family, church: church, account: parent) }

  before { use_tenant_host!(church) }

  def json = JSON.parse(response.body)

  def turn_off(*features)
    church.update!(disabled_features: features)
  end

  describe "gated endpoints" do
    # [feature, who asks, verb, path]
    GATED = [
      ["tasks",        :admin,  :get, "/api/v1/admin/tasks"],
      ["tasks",        :admin,  :get, "/api/v1/my_tasks"],
      ["time_card",    :admin,  :get, "/api/v1/time_card"],
      ["time_card",    :admin,  :get, "/api/v1/admin/time_entries"],
      ["time_card",    :admin,  :get, "/api/v1/admin/time_categories"],
      ["family_posts", :parent, :get, "/api/v1/family_posts"],
      ["family_posts", :admin,  :get, "/api/v1/admin/family_posts"],
      ["family_posts", :admin,  :get, "/api/v1/admin/tagged_posts"],
      ["feedback",     :parent, :get, "/api/v1/feedback"],
      ["feedback",     :admin,  :get, "/api/v1/admin/feedback"],
    ].freeze

    GATED.each do |feature, who, verb, path|
      it "#{verb.upcase} #{path} works with #{feature} on and answers 404 with it off" do
        account = who == :admin ? admin : parent

        send(verb, path, headers: auth_headers(account))
        expect(response).to have_http_status(:ok)

        turn_off(feature)
        send(verb, path, headers: auth_headers(account))
        expect(response).to have_http_status(:not_found)
        expect(json["code"]).to eq("feature_disabled")
      end
    end
  end

  describe "prayer requests" do
    let(:other_family) { create(:spirely_family, church: church) }
    let!(:request_post) do
      create(:spirely_family_post, church: church, family: other_family, post_type: "prayer_request",
                                   status: "approved", audience: "church")
    end
    let!(:milestone) do
      create(:spirely_family_post, church: church, family: other_family, post_type: "milestone",
                                   status: "approved", audience: "church", body: "First steps!")
    end

    it "leaves prayer requests and praise reports out of the family feed" do
      turn_off("prayer")
      get "/api/v1/family_posts", headers: auth_headers(parent)

      expect(response).to have_http_status(:ok)
      expect(json["family_posts"].map { |p| p["id"] }).to eq([milestone.id])
    end

    it "leaves them out of staff's list too" do
      turn_off("prayer")
      get "/api/v1/admin/family_posts", headers: auth_headers(admin)

      expect(json["family_posts"].map { |p| p["id"] }).to eq([milestone.id])
    end

    it "won't open one" do
      turn_off("prayer")
      get "/api/v1/family_posts/#{request_post.id}", headers: auth_headers(parent)
      expect(response).to have_http_status(:not_found)
    end

    it "won't take a new one" do
      turn_off("prayer")
      post "/api/v1/family_posts", params: { family_post: { post_type: "prayer_request", body: "Pray for us" } },
                                   headers: auth_headers(parent)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to include("Prayer requests and praise reports are turned off.")
      expect(family.family_posts).to be_empty
    end

    it "still takes other kinds of posts" do
      turn_off("prayer")
      post "/api/v1/family_posts", params: { family_post: { post_type: "milestone", body: "Lost a tooth" } },
                                   headers: auth_headers(parent)
      expect(response).to have_http_status(:created)
    end

    it "answers 404 to praying, for families and staff" do
      turn_off("prayer")

      post "/api/v1/family_posts/#{request_post.id}/prayer", headers: auth_headers(parent)
      expect(response).to have_http_status(:not_found)
      post "/api/v1/admin/family_posts/#{request_post.id}/prayer", headers: auth_headers(admin)
      expect(response).to have_http_status(:not_found)
      expect(request_post.prayers).to be_empty
    end

    it "is off whenever family posts are off" do
      turn_off("family_posts")
      expect(church.reload.feature_enabled?("prayer")).to be(false)
    end
  end

  describe "photo and attachment links" do
    it "stop working for family posts once family posts are off" do
      post_record = create(:spirely_family_post, church: church, family: family, post_type: "milestone", body: "Hi")
      post_record.attach_photos([fixture_file_upload("store-item.png", "image/png")])
      signed = post_record.photos.first.blob.signed_id(purpose: "family_post_photo")

      get "/api/v1/family_post_photos/#{signed}"
      expect(response).to have_http_status(:redirect)

      turn_off("family_posts")
      get "/api/v1/family_post_photos/#{signed}"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/admin/features" do
    it "lists every feature with whether it's on" do
      turn_off("time_card")
      get "/api/v1/admin/features", headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      features = json["features"].index_by { |f| f["id"] }
      expect(features.keys).to eq(%w[volunteers tasks time_card family_posts prayer feedback events surveys])
      expect(features["time_card"]).to include("label" => "Time card", "enabled" => false)
      expect(features["tasks"]).to include("enabled" => true)
      expect(features["volunteers"]).to include("module" => "kidsmin")
      expect(features["tasks"]["description"]).to be_present
    end

    it "is for admins only" do
      get "/api/v1/admin/features", headers: auth_headers(parent)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "PATCH /api/v1/admin/features" do
    it "saves which features are off" do
      patch "/api/v1/admin/features", params: { disabled_features: %w[tasks events] }, headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(church.reload.disabled_features).to contain_exactly("tasks", "events")
      expect(json["enabled_features"]).to eq(%w[volunteers time_card family_posts prayer feedback surveys])
    end

    it "turns everything back on with an empty list" do
      turn_off("tasks")
      patch "/api/v1/admin/features", params: { disabled_features: [] }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(church.reload.disabled_features).to eq([])
    end

    it "rejects a feature it doesn't know" do
      patch "/api/v1/admin/features", params: { disabled_features: %w[tasks teleporter] }, headers: auth_headers(admin)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(church.reload.disabled_features).to eq([])
    end

    it "is for admins only" do
      patch "/api/v1/admin/features", params: { disabled_features: %w[tasks] }, headers: auth_headers(parent)

      expect(response).to have_http_status(:forbidden)
      expect(church.reload.disabled_features).to eq([])
    end
  end

  describe "GET /api/v1/me" do
    it "says which features are on, and drops links to ones that are off" do
      turn_off("time_card", "family_posts")
      get "/api/v1/me", headers: auth_headers(admin)

      expect(json["enabled_features"]).to eq(%w[volunteers tasks feedback events surveys])
      expect(json["time_card"]).to be(false)
      expect(json["post_to_families"]).to be(false)
    end

    # The mobile app shows staff tiles (Tasks, New families, Birthdays) on
    # this, so it mustn't go away with the time card (5ST-82).
    it "still says who's staff with the time card off" do
      staff = create(:account)
      create(:membership, church: church, account: staff, role: "family", staff: true)
      turn_off("time_card")

      get "/api/v1/me", headers: auth_headers(admin)
      expect(json).to include("time_card" => false, "staff_member" => true)

      get "/api/v1/me", headers: auth_headers(staff)
      expect(json["staff_member"]).to be(true)

      get "/api/v1/me", headers: auth_headers(parent)
      expect(json["staff_member"]).to be(false)
    end
  end
end
