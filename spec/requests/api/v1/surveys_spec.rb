require "rails_helper"

# Anonymous surveys (5ST-84): parents answer on the church's site with no
# sign-in; admins see the results.
RSpec.describe "Surveys API", type: :request do
  let(:church) { create(:church) }
  let(:admin)  { create(:account) }
  let(:parent) { create(:account) }
  let!(:survey) { Spirely::Survey.from_template!(church, "kids_church_family", slug: "year-end-2026") }

  before do
    create(:membership, :admin, church: church, account: admin)
    create(:membership, church: church, account: parent)
    use_tenant_host!(church)
  end

  def json = JSON.parse(response.body)

  describe "GET /api/v1/surveys (the home page's card)" do
    it "lists open surveys shown on the home page, with no sign-in" do
      Spirely::Survey.from_template!(church, "kids_church_family", slug: "hidden").update!(show_on_home: false)
      Spirely::Survey.from_template!(church, "kids_church_family", slug: "old").update!(status: "closed")
      Spirely::Survey.from_template!(create(:church), "kids_church_family", slug: "elsewhere")

      get "/api/v1/surveys"
      expect(response).to have_http_status(:ok)
      expect(json["surveys"]).to eq([{ "slug" => "year-end-2026", "title" => "Kids Church Family Survey",
                                       "blurb" => survey.home_blurb }])
    end
  end

  describe "GET /api/v1/surveys/:slug" do
    it "shows the questions, with no sign-in" do
      get "/api/v1/surveys/year-end-2026"
      expect(response).to have_http_status(:ok)
      expect(json).to include("title" => "Kids Church Family Survey", "open" => true, "church_name" => church.name)
      expect(json["questions"].size).to eq(12)
      expect(json["questions"].first).to include("id" => "age_groups", "section" => "About your family", "type" => "multi")
    end

    it "says a closed survey is closed, without the questions" do
      survey.update!(status: "closed")
      get "/api/v1/surveys/year-end-2026"
      expect(response).to have_http_status(:ok)
      expect(json).to include("open" => false, "questions" => [])
    end

    it "404s for another church's survey" do
      host! "#{create(:church).slug}.example.test"
      get "/api/v1/surveys/year-end-2026"
      expect(response).to have_http_status(:not_found)
    end

    it "404s while the church has surveys turned off" do
      church.update!(disabled_features: ["surveys"])
      get "/api/v1/surveys/year-end-2026"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/surveys/:slug/responses" do
    let(:answers) do
      { attendance: { value: "Every week" },
        most_important: { value: ["Bible knowledge", "Other"], other: "Kindness" },
        satisfied: { value: "Very satisfied", follow_up: "More family nights" } }
    end

    it "saves an anonymous response, with no sign-in" do
      post "/api/v1/surveys/year-end-2026/responses", params: { answers: answers }, as: :json
      expect(response).to have_http_status(:created)
      expect(survey.responses.sole.answers).to eq(
        "attendance" => { "value" => "Every week" },
        "most_important" => { "value" => ["Bible knowledge", "Other"], "other" => "Kindness" },
        "satisfied" => { "value" => "Very satisfied", "follow_up" => "More family nights" },
      )
    end

    it "saves nothing about who sent it, even when signed in" do
      post "/api/v1/surveys/year-end-2026/responses", params: { answers: answers }, headers: auth_headers(parent), as: :json
      expect(response).to have_http_status(:created)
      expect(survey.responses.sole.attributes.keys).to contain_exactly("id", "survey_id", "answers", "created_at")
    end

    it "needs at least one answer" do
      post "/api/v1/surveys/year-end-2026/responses", params: { answers: { nope: { value: "x" } } }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["code"]).to eq("no_answers")
      expect(survey.responses.count).to eq(0)
    end

    it "won't take answers once it's closed" do
      survey.update!(status: "closed")
      post "/api/v1/surveys/year-end-2026/responses", params: { answers: answers }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["code"]).to eq("closed")
    end

    # A hidden field people never see; bots fill it in.
    it "acts as if it saved a bot's answers, and doesn't" do
      post "/api/v1/surveys/year-end-2026/responses", params: { answers: answers, website: "http://spam.example" }, as: :json
      expect(response).to have_http_status(:created)
      expect(survey.responses.count).to eq(0)
    end
  end

  describe "GET /api/v1/admin/surveys" do
    it "lists the church's surveys with how many answered" do
      survey.responses.create!(answers: { "attendance" => { "value" => "Every week" } })
      get "/api/v1/admin/surveys", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(json["surveys"]).to eq([{ "id" => survey.id, "slug" => "year-end-2026", "title" => "Kids Church Family Survey",
                                       "status" => "open", "show_on_home" => true, "response_count" => 1,
                                       "opened_at" => survey.opened_at.as_json, "closed_at" => nil }])
    end

    it "is for admins only" do
      get "/api/v1/admin/surveys", headers: auth_headers(parent)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /api/v1/admin/surveys/:id" do
    it "shows the results" do
      survey.responses.create!(answers: survey.clean_answers("satisfied" => { "value" => "Very satisfied", "follow_up" => "Love it" }))
      get "/api/v1/admin/surveys/#{survey.id}", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(json["survey"]).to include("response_count" => 1)
      satisfied = json["results"].find { |r| r["id"] == "satisfied" }
      expect(satisfied).to include("answered" => 1, "follow_up" => "What's one thing we could do better?", "follow_ups" => ["Love it"])
      expect(satisfied["counts"].first).to eq(["Extremely satisfied", 0])
    end

    it "404s for another church's survey" do
      other = Spirely::Survey.from_template!(create(:church), "kids_church_family", slug: "x")
      get "/api/v1/admin/surveys/#{other.id}", headers: auth_headers(admin)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /api/v1/admin/surveys/:id" do
    it "closes and reopens it, and takes it off the home page" do
      patch "/api/v1/admin/surveys/#{survey.id}", params: { survey: { status: "closed" } }, headers: auth_headers(admin), as: :json
      expect(response).to have_http_status(:ok)
      expect(survey.reload).to have_attributes(status: "closed")
      expect(survey.closed_at).to be_present

      patch "/api/v1/admin/surveys/#{survey.id}", params: { survey: { status: "open", show_on_home: false } }, headers: auth_headers(admin), as: :json
      expect(survey.reload).to have_attributes(status: "open", show_on_home: false, closed_at: nil)
    end

    it "rejects a status it doesn't know" do
      patch "/api/v1/admin/surveys/#{survey.id}", params: { survey: { status: "paused" } }, headers: auth_headers(admin), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "is for admins only" do
      patch "/api/v1/admin/surveys/#{survey.id}", params: { survey: { status: "closed" } }, headers: auth_headers(parent), as: :json
      expect(response).to have_http_status(:forbidden)
      expect(survey.reload.status).to eq("open")
    end
  end
end
