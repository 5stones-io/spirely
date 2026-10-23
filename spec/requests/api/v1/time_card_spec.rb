require "rails_helper"

# Time card: staff log hours toward category codes; admins see everyone's.
RSpec.describe "Time card", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:church)     { create(:church) }
  let(:facilities) { church.time_categories.create!(code: "fac", name: "Facilities") }
  let(:events)     { church.time_categories.create!(code: "EVT", name: "Events") }
  let(:admin)      { create(:account, first_name: "Jenna", last_name: "Park").tap { |a| create(:membership, :admin, church: church, account: a) } }
  let(:sam)        { create(:account, first_name: "Sam", last_name: "Ortiz") }
  let!(:sam_member) { create(:membership, church: church, account: sam, staff: true) }

  before do
    use_tenant_host!(church)
    travel_to Time.zone.parse("2026-10-28 12:00") # a Wednesday, after this feature's migrations
  end
  after { travel_back }

  def json = JSON.parse(response.body)

  it "logs hours toward a category, and shows the week with totals" do
    post "/api/v1/time_entries", params: { time_category_id: facilities.id, title: "Fixed the gym door", hours: 1.5, worked_on: "2026-10-27" },
                                 headers: auth_headers(sam), as: :json
    expect(response).to have_http_status(:created)
    expect(json).to include("title" => "Fixed the gym door", "hours" => 1.5)
    expect(json["category"]).to include("code" => "FAC")

    get "/api/v1/time_card", headers: auth_headers(sam)
    expect(json).to include("name" => "Sam Ortiz", "week_of" => "2026-10-26", "week_end" => "2026-11-01", "total_hours" => 1.5)
    expect(json["totals"].sole).to include("hours" => 1.5)
  end

  it "takes the category and title from a task assigned to them" do
    task = church.tasks.create!(title: "Set up for Trunk or Treat", assignee_membership_id: sam_member.id, time_category: events)

    get "/api/v1/time_card", headers: auth_headers(sam)
    expect(json["tasks"].sole).to include("title" => "Set up for Trunk or Treat")

    post "/api/v1/time_entries", params: { task_id: task.id, hours: 3, worked_on: "2026-10-28" }, headers: auth_headers(sam), as: :json
    expect(json).to include("title" => "Set up for Trunk or Treat", "task" => { "id" => task.id, "title" => "Set up for Trunk or Treat" })
    expect(json["category"]).to include("code" => "EVT")
  end

  it "needs a category when there's no task, and keeps hours sensible" do
    post "/api/v1/time_entries", params: { title: "Misc", hours: 2, worked_on: "2026-10-28" }, headers: auth_headers(sam), as: :json
    expect(response).to have_http_status(:unprocessable_entity)

    post "/api/v1/time_entries", params: { time_category_id: facilities.id, title: "Too long", hours: 30, worked_on: "2026-10-28" },
                                 headers: auth_headers(sam), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "only lets people edit or delete their own entries" do
    entry = church.time_entries.create!(membership: admin.memberships.first, time_category: facilities, title: "Admin hours", hours: 1, worked_on: Date.current)
    patch "/api/v1/time_entries/#{entry.id}", params: { hours: 9 }, headers: auth_headers(sam), as: :json
    expect(response).to have_http_status(:not_found)
    delete "/api/v1/time_entries/#{entry.id}", headers: auth_headers(sam)
    expect(response).to have_http_status(:not_found)
    expect(entry.reload.hours).to eq(1)
  end

  it "tells a staff member's home it can link to the time card" do
    get "/api/v1/me", headers: auth_headers(sam)
    expect(json["time_card"]).to be(true)
  end

  it "is only for staff and admins" do
    family = create(:account).tap { |a| create(:membership, church: church, account: a) }
    get "/api/v1/time_card", headers: auth_headers(family)
    expect(response).to have_http_status(:forbidden)

    get "/api/v1/time_card", headers: auth_headers(admin)
    expect(response).to have_http_status(:ok)
  end

  describe "for admins" do
    before do
      church.time_entries.create!(membership: sam_member, time_category: facilities, title: "Gym door", hours: 1.5, worked_on: Date.new(2026, 10, 27))
      church.time_entries.create!(membership: sam_member, time_category: events, title: "Setup", hours: 3, worked_on: Date.new(2026, 10, 28))
    end

    it "shows everyone's hours with totals, filtered by category" do
      get "/api/v1/admin/time_entries", headers: auth_headers(admin)
      expect(json["total_hours"]).to eq(4.5)
      expect(json["people_totals"].sole).to include("name" => "Sam Ortiz", "hours" => 4.5)
      expect(json["people"].map { |p| p["name"] }).to include("Sam Ortiz", "Jenna Park")

      get "/api/v1/admin/time_entries", params: { time_category_id: events.id }, headers: auth_headers(admin)
      expect(json["entries"].map { |e| e["title"] }).to eq(["Setup"])
    end

    it "downloads a CSV for payroll" do
      get "/api/v1/admin/time_entries.csv", params: { from: "2026-10-26", to: "2026-11-01" }, headers: auth_headers(admin)
      expect(response.media_type).to eq("text/csv")
      rows = CSV.parse(response.body)
      expect(rows.first).to eq(["Date", "Name", "Email", "Category code", "Category", "Task", "Title", "Description", "Hours"])
      expect(rows[1]).to include("2026-10-27", "Sam Ortiz", "FAC", "Facilities", "Gym door", "1.5")
    end

    it "manages categories, turned off rather than deleted" do
      post "/api/v1/admin/time_categories", params: { code: "ofc", name: "Office" }, headers: auth_headers(admin), as: :json
      expect(json).to include("code" => "OFC", "active" => true)
      patch "/api/v1/admin/time_categories/#{json["id"]}", params: { active: false }, headers: auth_headers(admin), as: :json
      expect(json["active"]).to be(false)

      post "/api/v1/admin/time_categories", params: { code: "FAC", name: "Again" }, headers: auth_headers(admin), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "marks a member as staff from Settings → Team" do
      other = create(:account, first_name: "Lee", last_name: "Smith", email: "lee@example.com")
      member = create(:membership, church: church, account: other)

      get "/api/v1/admin/staff/candidates", params: { q: "lee" }, headers: auth_headers(admin)
      expect(json["members"].map { |m| m["id"] }).to eq([member.id])

      patch "/api/v1/admin/staff/members/#{member.id}", params: { staff: true }, headers: auth_headers(admin), as: :json
      expect(member.reload.staff).to be(true)

      get "/api/v1/admin/staff", headers: auth_headers(admin)
      expect(json["time_card_staff"].map { |m| m["email"] }).to contain_exactly("lee@example.com", sam.email)
    end

    it "is admin-only" do
      get "/api/v1/admin/time_entries", headers: auth_headers(sam)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
