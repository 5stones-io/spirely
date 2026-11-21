require "rails_helper"

# Create Account (5ST-85): a parent asks for an account on the church's
# site with no sign-in, finishes a new-family form from the emailed link,
# and staff approve it.
RSpec.describe "Family sign-ups API", type: :request do
  include ActiveJob::TestHelper

  let(:church) { create(:church) }
  let(:admin)  { create(:account) }
  let(:parent) { create(:account) }
  let(:details) do
    { first_name: "Pat", last_name: "Rivera", address: "12 Oak St",
      children: [{ first_name: "Mia", birthdate: "2019-04-02", allergies: "" }] }
  end

  before do
    create(:membership, :admin, church: church, account: admin)
    create(:membership, church: church, account: parent)
    use_tenant_host!(church)
  end

  after { ActionMailer::Base.deliveries.clear }

  def json = JSON.parse(response.body)

  describe "POST /api/v1/account_requests" do
    it "answers the same whether or not we know them, with no sign-in" do
      create(:spirely_family, church: church, account: nil, phone: "5552013344", email: "onfile@example.com")

      post "/api/v1/account_requests", params: { phone: "555-201-3344", email: "a@example.com" }, as: :json
      known = [response.status, response.body]
      post "/api/v1/account_requests", params: { phone: "555-777-8888", email: "b@example.com" }, as: :json

      expect([response.status, response.body]).to eq(known)
      expect(response).to have_http_status(:accepted)
    end

    it "says what's wrong with a phone or email that isn't one" do
      post "/api/v1/account_requests", params: { phone: "12", email: "a@example.com" }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to include("Phone")
    end

    it "404s while the church has sign-ups turned off" do
      church.update!(disabled_features: ["family_signup"])
      post "/api/v1/account_requests", params: { phone: "5552013344", email: "a@example.com" }, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "the new-family form" do
    let!(:signup) { church.family_signups.create!(phone: "5552013344", email: "pat@example.com") }

    it "shows the phone and email it was started with" do
      get "/api/v1/family_signups/#{signup.token}"
      expect(response).to have_http_status(:ok)
      expect(json).to include("status" => "started", "phone" => "5552013344", "email" => "pat@example.com",
                              "church_name" => church.name, "expired" => false)
    end

    it "takes the family's details and emails the church's admins" do
      perform_enqueued_jobs do
        patch "/api/v1/family_signups/#{signup.token}", params: details, as: :json
      end
      expect(response).to have_http_status(:ok)
      expect(json["status"]).to eq("submitted")
      expect(ActionMailer::Base.deliveries.map(&:to).flatten).to eq([admin.email])
    end

    it "says what's missing" do
      patch "/api/v1/family_signups/#{signup.token}", params: details.merge(children: []), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to be_present
    end

    it "won't take it twice, or after the link expires" do
      patch "/api/v1/family_signups/#{signup.token}", params: details, as: :json
      patch "/api/v1/family_signups/#{signup.token}", params: details, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["code"]).to eq("already_sent")

      expired = church.family_signups.create!(phone: "5550001111", email: "x@example.com")
      expired.update!(expires_at: 1.minute.ago)
      patch "/api/v1/family_signups/#{expired.token}", params: details, as: :json
      expect(json["code"]).to eq("expired")
    end

    it "404s for another church's link" do
      host! "#{create(:church).slug}.example.test"
      get "/api/v1/family_signups/#{signup.token}"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "admin" do
    let!(:signup) do
      church.family_signups.create!(phone: "5552013344", email: "pat@example.com").tap { |s| s.submit!(details.deep_stringify_keys) }
    end

    it "lists sign-ups waiting for staff, with the likely match" do
      family = create(:spirely_family, church: church, family_name: "Rivera Family")
      signup.update!(matched_family: family)
      church.family_signups.create!(phone: "5550001111", email: "x@example.com") # never finished

      get "/api/v1/admin/family_signups", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(json["family_signups"].size).to eq(1)
      expect(json["family_signups"].first).to include(
        "id" => signup.id, "phone" => "5552013344", "email" => "pat@example.com", "status" => "submitted",
        "first_name" => "Pat", "last_name" => "Rivera", "address" => "12 Oak St",
        "matched_family" => { "id" => family.id, "name" => "Rivera Family" },
      )
      expect(json["family_signups"].first["children"].first).to include("first_name" => "Mia", "birthdate" => "2019-04-02")
    end

    it "approves one: creates the family and sends the invite" do
      post "/api/v1/admin/family_signups/#{signup.id}/approve", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(json["family_signup"]).to include("status" => "approved")
      expect(church.families.find(json["family_signup"]["family_id"]).children.count).to eq(1)
    end

    it "declines one" do
      post "/api/v1/admin/family_signups/#{signup.id}/decline", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(signup.reload.status).to eq("declined")
    end

    it "won't approve one twice" do
      post "/api/v1/admin/family_signups/#{signup.id}/approve", headers: auth_headers(admin)
      post "/api/v1/admin/family_signups/#{signup.id}/approve", headers: auth_headers(admin)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(church.families.count).to eq(1)
    end

    it "is for admins only" do
      get "/api/v1/admin/family_signups", headers: auth_headers(parent)
      expect(response).to have_http_status(:forbidden)
      post "/api/v1/admin/family_signups/#{signup.id}/approve", headers: auth_headers(parent)
      expect(response).to have_http_status(:forbidden)
      expect(church.families).to be_empty
    end
  end
end
