require "rails_helper"

RSpec.describe Spirely::PcoServicesSyncJob do
  SERVICES = "https://api.planningcenteronline.com/services/v2".freeze
  PLAN_PATH = "/service_types/st1/plans/pl1".freeze

  let(:church) { create(:church, enabled_modules: ["kudos"]) }
  let(:sunday) { 3.days.ago.change(hour: 9) }

  before do
    Spirely.configuration.encryption_key = SecureRandom.hex(32)
    create(:spirely_church_integration, church: church, access_token: "token")
    allow_any_instance_of(described_class).to receive(:sleep)
  end

  def stub_pco(path, body, status: 200)
    stub_request(:get, "#{SERVICES}#{path}").with(query: hash_including({}))
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  def plan(id, sort_date)
    { "type" => "Plan", "id" => id,
      "attributes" => { "title" => "Faithful", "series_title" => "Psalms", "dates" => sort_date.to_date.to_fs(:long),
                        "sort_date" => sort_date.iso8601 } }
  end

  def plan_time(id, starts_at, type: "service", teams: ["t1"])
    attrs = { "name" => type.capitalize, "time_type" => type, "starts_at" => starts_at.iso8601,
              "ends_at" => (starts_at + 1.hour).iso8601 }
    attrs["scheduled_team_ids"] = teams unless teams == :missing
    { "type" => "PlanTime", "id" => id, "attributes" => attrs }
  end

  def member(id, person_id, status, team: "t1", position: "Guitar", declined: [])
    { "type" => "PlanPerson", "id" => id,
      "attributes" => { "name" => "Lee Smith", "status" => status, "team_position_name" => position },
      "relationships" => {
        "person" => { "data" => { "type" => "Person", "id" => person_id } },
        "team" => { "data" => { "type" => "Team", "id" => team } },
        "declined_plan_times" => { "data" => declined.map { |t| { "type" => "PlanTime", "id" => t } } },
      } }
  end

  def stub_full_sync(members: nil, times: nil)
    stub_pco("/service_types", { "data" => [{ "type" => "ServiceType", "id" => "st1", "attributes" => { "name" => "Sunday Services" } }] })
    stub_pco("/service_types/st1/plans", { "data" => [plan("pl1", sunday)] })
    stub_pco("#{PLAN_PATH}/plan_times", { "data" => times || [
      plan_time("pt1", sunday - 2.hours, type: "rehearsal"), plan_time("pt2", sunday), plan_time("pt3", sunday + 2.hours),
    ] })
    stub_pco("#{PLAN_PATH}/team_members", {
      "data" => members || [member("pp1", "p1", "C", declined: ["pt3"]), member("pp2", "p2", "U", team: "t2", position: nil)],
      "included" => [
        { "type" => "Person", "id" => "p1", "attributes" => { "first_name" => "Lee", "last_name" => "Smith" } },
        { "type" => "Team", "id" => "t1", "attributes" => { "name" => "Band" } },
        { "type" => "Team", "id" => "t2", "attributes" => { "name" => "Production" } },
      ],
    })
  end

  it "mirrors service types, past plans, their times and who was scheduled" do
    stub_full_sync
    expect(Spirely::KudosEarningJob).to receive(:perform_later).with(church.id)
    described_class.perform_now(church.id)

    expect(church.service_types.sole).to have_attributes(name: "Sunday Services")
    plan = church.service_plans.sole
    expect(plan).to have_attributes(title: "Faithful", series_title: "Psalms", people_synced_at: be_present)
    expect(plan.sort_date).to be_within(1.second).of(sunday)
    expect(plan.ends_at).to be_within(1.second).of(sunday + 3.hours)
    expect(plan.times.order(:starts_at).pluck(:time_type, :team_ids)).to eq([["rehearsal", ["t1"]], ["service", ["t1"]], ["service", ["t1"]]])

    lee = church.people.find_by!(pco_person_id: "p1")
    expect(lee).to have_attributes(first_name: "Lee", last_name: "Smith")
    expect(plan.plan_people.find_by!(pco_plan_person_id: "pp1"))
      .to have_attributes(person: lee, status: "C", team_name: "Band", position_name: "Guitar", declined_time_ids: ["pt3"])
    # A person PCO didn't include falls back to the name on the plan person.
    expect(plan.plan_people.find_by!(pco_plan_person_id: "pp2"))
      .to have_attributes(status: "U", team_name: "Production", person: have_attributes(first_name: "Lee", pco_person_id: "p2"))
    expect(church.sync_setting.services_last_synced_at).to be_present
  end

  it "is safe to run again, and follows changes to the schedule" do
    stub_full_sync
    described_class.perform_now(church.id)
    stub_full_sync(members: [member("pp1", "p1", "Confirmed", position: "Bass")])
    described_class.perform_now(church.id)

    plan = church.service_plans.sole
    expect(church.service_types.count).to eq(1)
    expect(plan.times.count).to eq(3)
    expect(plan.plan_people.sole).to have_attributes(pco_plan_person_id: "pp1", status: "C", position_name: "Bass")
  end

  it "treats a time with no scheduled_team_ids as open to every team" do
    stub_full_sync(times: [plan_time("pt2", sunday, teams: :missing)])
    described_class.perform_now(church.id)

    expect(church.service_plans.sole.times.sole.team_ids).to be_nil
  end

  it "stops paging once plans are older than the window" do
    old = plan("pl0", (described_class::HISTORY_WINDOW + 1.week).ago)
    stub_full_sync
    stub_pco("/service_types/st1/plans", { "data" => [plan("pl1", sunday), old],
                                           "links" => { "next" => "#{SERVICES}/service_types/st1/plans?offset=25" } })
    next_page = stub_request(:get, "#{SERVICES}/service_types/st1/plans").with(query: hash_including("offset" => "25"))
    described_class.perform_now(church.id)

    expect(next_page).not_to have_been_requested
    expect(church.service_plans.pluck(:pco_plan_id)).to eq(["pl1"])
  end

  it "doesn't re-read the schedule of plans past the recheck window" do
    stub_full_sync
    described_class.perform_now(church.id)
    church.service_plans.sole.update!(sort_date: 3.weeks.ago)
    WebMock.reset!
    stub_pco("/service_types", { "data" => [{ "type" => "ServiceType", "id" => "st1", "attributes" => { "name" => "Sunday Services" } }] })
    stub_pco("/service_types/st1/plans", { "data" => [plan("pl1", 3.weeks.ago)] })
    described_class.perform_now(church.id)

    expect(a_request(:get, /team_members/)).not_to have_been_made
  end

  it "does nothing unless Kudos is on" do
    church.update!(enabled_modules: [])
    described_class.perform_now(church.id)
    expect(a_request(:get, /services/)).not_to have_been_made
  end

  it "records a 403 instead of raising" do
    stub_pco("/service_types", { "errors" => [{ "title" => "Forbidden" }] }, status: 403)
    described_class.perform_now(church.id)
    expect(church.reload.sync_setting.services_access_denied_at).to be_present
  end
end
