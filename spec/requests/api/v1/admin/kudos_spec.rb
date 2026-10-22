require "rails_helper"

RSpec.describe "/api/v1/admin/kudos", type: :request do
  include ActiveJob::TestHelper
  around do |ex|
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    ex.run
  ensure
    ActiveJob::Base.queue_adapter = original
  end

  let(:church) { create(:church, enabled_modules: ["kudos"]) }
  let(:admin)  { create(:account, first_name: "Pastor", last_name: "Mike").tap { |a| create(:membership, :admin, church: church, account: a) } }
  let!(:sarah) { create(:spirely_person, church: church, first_name: "Sarah", last_name: "Mitchell", pco_person_id: "p1") }
  let!(:emma)  { create(:spirely_person, church: church, first_name: "Emma", last_name: "Johnson", pco_person_id: "p2", child: true) }

  before { use_tenant_host!(church) }

  def json = JSON.parse(response.body)

  def award(person, points, note = "Thanks")
    Spirely::Kudos.new(church).award!(pco_person_id: person.pco_person_id, points: points, note: note, by_account: admin)
  end

  it "shows the overview" do
    award(sarah, 100)
    award(emma, 50)
    award(emma, -10, "Correction")

    get "/api/v1/admin/kudos", headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(json).to include("points_held" => 140, "people_count" => 2)
    expect(json["month"]).to include("awarded" => 150, "awards_count" => 2, "awarders_count" => 1, "deducted" => 10, "deductions_count" => 1)
    expect(json["recent"].first).to include("points" => -10, "note" => "Correction", "by" => "Pastor Mike")
  end

  it "lists people with points, highest balance first, filtered by audience" do
    award(sarah, 100)
    award(emma, 300)

    get "/api/v1/admin/kudos/people", headers: auth_headers(admin)
    expect(json["people"].map { |p| [p["name"], p["balance"]] }).to eq([["Emma Johnson", 300], ["Sarah Mitchell", 100]])
    expect(json["meta"]["total_count"]).to eq(2)

    get "/api/v1/admin/kudos/people", params: { audience: "adults" }, headers: auth_headers(admin)
    expect(json["people"].map { |p| p["name"] }).to eq(["Sarah Mitchell"])
  end

  it "searches everyone, with or without points" do
    get "/api/v1/admin/kudos/people", params: { q: "emma" }, headers: auth_headers(admin)
    expect(json["people"]).to match([a_hash_including("pco_person_id" => "p2", "balance" => 0, "kid" => true)])
  end

  it "shows one person's balance and history" do
    award(emma, 50)
    award(emma, -20, "Entered twice")

    get "/api/v1/admin/kudos/people/p2", headers: auth_headers(admin)

    expect(json).to include("name" => "Emma Johnson", "balance" => 30, "earned" => 50, "deducted" => 20, "more_history" => false)
    expect(json["history"].map { |e| [e["points"], e["balance_after"]] }).to eq([[-20, 30], [50, 50]])
  end

  it "awards and deducts points" do
    post "/api/v1/admin/kudos/entries", params: { pco_person_id: "p1", points: 25, note: "Set up chairs" },
         headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:created)
    expect(json).to include("points" => 25, "balance" => 25)

    post "/api/v1/admin/kudos/entries", params: { pco_person_id: "p1", points: -30, note: "Too many" },
         headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(json["error"]).to match(/only has 25 points/)
  end

  it "updates the earning start date" do
    patch "/api/v1/admin/kudos/settings", params: { earning_starts_on: "2026-09-01" }, headers: auth_headers(admin), as: :json
    expect(json).to include("earning_starts_on" => "2026-09-01")
    expect(church.kudos_setting.earning_starts_on).to eq(Date.new(2026, 9, 1))
  end

  it "sets earning rates, including per-event ones, and posts points owed at the new rates" do
    create(:spirely_attendance, church: church, person: emma, pco_event_id: "wed", event_name: "Rangers")

    patch "/api/v1/admin/kudos/settings",
          params: { checkin_points: 10, group_points: 5, event_rates: [{ pco_event_id: "wed", points: 20 }] },
          headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:ok)
    expect(json).to include("checkin_points" => 10, "group_points" => 5)
    expect(json["event_rates"]).to eq([{ "pco_event_id" => "wed", "event_name" => "Rangers", "points" => 20 }])
    expect(json["events"].map { |e| e["event_name"] }).to eq(["Rangers"])
    expect(Spirely::KudosEarningJob).to have_been_enqueued.with(church.id)

    perform_enqueued_jobs
    expect(Spirely::Kudos.new(church).totals(emma)[:balance]).to eq(20)
  end

  it "sets the time-served rates and whether rehearsals count" do
    patch "/api/v1/admin/kudos/settings",
          params: { service_hour_points: 10, service_flat_points: 25, count_rehearsals: true },
          headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:ok)
    expect(json).to include("service_hour_points" => 10, "service_flat_points" => 25, "count_rehearsals" => true,
                            "services_last_synced_at" => nil, "services_access_denied_at" => nil)
  end

  it "shows the plan behind time-served points in someone's history" do
    sunday = 3.days.ago.change(hour: 9)
    type = church.service_types.create!(pco_service_type_id: "st1", name: "Sunday Services")
    plan = type.plans.create!(church: church, pco_plan_id: "pl1", title: "Faithful", dates: "October 19, 2026",
                              sort_date: sunday, ends_at: sunday + 1.hour)
    plan.times.create!(church: church, pco_plan_time_id: "pt1", name: "9am", time_type: "service", team_ids: ["t1"],
                       starts_at: sunday, ends_at: sunday + 90.minutes)
    plan.plan_people.create!(church: church, person: sarah, pco_plan_person_id: "pp1", status: "C", pco_team_id: "t1",
                             team_name: "Band", position_name: "Guitar")
    Spirely::KudosSetting.for(church).update!(earning_starts_on: 1.week.ago.to_date, rates: { "service_hour" => 10 })
    Spirely::Kudos.new(church).post_earned_points!

    get "/api/v1/admin/kudos/people/p1", headers: auth_headers(admin)
    entry = json["history"].sole
    expect(entry).to include("points" => 15, "source" => "service", "note" => "Served · Sunday Services · Faithful · 1.5 hours")
    expect(entry["serving"]).to include("plan" => "Sunday Services · Faithful", "dates" => "October 19, 2026",
                                        "hours" => 1.5, "flat" => false, "roles" => ["Band — Guitar"])
    expect(entry["serving"]["times"].sole).to include("name" => "9am", "time_type" => "service", "clock" => be_present)
  end

  it "rejects a rate that isn't a whole number from 0 up" do
    patch "/api/v1/admin/kudos/settings", params: { checkin_points: -5 }, headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:unprocessable_entity)

    patch "/api/v1/admin/kudos/settings", params: { checkin_points: "lots" }, headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  describe "promo codes" do
    it "creates, lists with uses, and turns off a code" do
      post "/api/v1/admin/kudos/promo_codes", params: { code: "fall-fest", label: "Fall Fest", points: 25, max_uses: 2 },
           headers: auth_headers(admin), as: :json
      expect(response).to have_http_status(:created)
      expect(json).to include("code" => "FALL-FEST", "status" => "active", "uses" => 0, "created_by" => "Pastor Mike")
      id = json["id"]

      Spirely::Kudos.new(church).claim_code!(code: "fall-fest", pco_person_id: "p1")
      get "/api/v1/admin/kudos/promo_codes", headers: auth_headers(admin)
      expect(json["promo_codes"].first).to include("uses" => 1, "points_given" => 25)

      patch "/api/v1/admin/kudos/promo_codes/#{id}", params: { active: false }, headers: auth_headers(admin), as: :json
      expect(json["status"]).to eq("off")
      patch "/api/v1/admin/kudos/promo_codes/#{id}", params: { active: true }, headers: auth_headers(admin), as: :json
      expect(json["status"]).to eq("active")
    end

    it "makes up a code when none is given, and refuses a duplicate" do
      post "/api/v1/admin/kudos/promo_codes", params: { label: "Welcome", points: 10 }, headers: auth_headers(admin), as: :json
      expect(json["code"]).to match(/\A[A-Z2-9]{6}\z/)

      post "/api/v1/admin/kudos/promo_codes", params: { code: json["code"].downcase, label: "Again", points: 10 },
           headers: auth_headers(admin), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to match(/already used/)
    end
  end

  it "is admin-only" do
    family_account = create(:account).tap { |a| create(:membership, church: church, account: a) }
    post "/api/v1/admin/kudos/entries", params: { pco_person_id: "p1", points: 25, note: "x" },
         headers: auth_headers(family_account), as: :json
    expect(response).to have_http_status(:forbidden)
    expect(church.points_entries.count).to eq(0)
  end

  it "404s when Kudos is off" do
    church.update!(enabled_modules: ["kidsmin"])
    get "/api/v1/admin/kudos", headers: auth_headers(admin)
    expect(response).to have_http_status(:not_found)
  end
end
