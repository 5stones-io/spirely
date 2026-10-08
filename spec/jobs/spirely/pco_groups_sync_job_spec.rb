require "rails_helper"

RSpec.describe Spirely::PcoGroupsSyncJob do
  PCO = "https://api.planningcenteronline.com/groups/v2".freeze

  let(:church) { create(:church, enabled_modules: ["smallgroups"]) }

  before do
    Spirely.configuration.encryption_key = SecureRandom.hex(32)
    create(:spirely_church_integration, church: church, access_token: "token")
    allow_any_instance_of(described_class).to receive(:sleep)
  end

  def stub_pco(path, body, status: 200)
    stub_request(:get, "#{PCO}#{path}").with(query: hash_including({}))
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  def person(id, first, email: nil, child: false)
    { "type" => "Person", "id" => id,
      "attributes" => { "first_name" => first, "last_name" => "Smith", "child" => child,
                        "email_addresses" => email ? [{ "address" => email, "primary" => true }] : [],
                        "phone_numbers" => [] } }
  end

  def membership(id, person_id, role)
    { "type" => "Membership", "id" => id, "attributes" => { "role" => role, "joined_at" => 1.year.ago.iso8601 },
      "relationships" => { "person" => { "data" => { "type" => "Person", "id" => person_id } } } }
  end

  def event(id, starts_at, canceled: false)
    { "type" => "Event", "id" => id,
      "attributes" => { "name" => "Weekly", "starts_at" => starts_at.iso8601, "ends_at" => (starts_at + 2.hours).iso8601,
                        "canceled" => canceled } }
  end

  def stub_full_sync(memberships: nil, groups: nil, applications: nil, events: nil)
    stub_pco("/group_types", { "data" => [
      { "type" => "GroupType", "id" => "gt1", "attributes" => { "name" => "Adult Groups", "color" => "#123456" } },
    ] })
    stub_pco("/groups", { "data" => groups || [
      { "type" => "Group", "id" => "g1",
        "attributes" => { "name" => "Tuesday Night", "schedule" => "Tuesdays at 7pm", "memberships_count" => 2,
                          "description_as_plain_text" => "Study", "archived_at" => nil },
        "relationships" => { "group_type" => { "data" => { "type" => "GroupType", "id" => "gt1" } },
                             "location" => { "data" => { "type" => "Location", "id" => "loc1" } } } },
      { "type" => "Group", "id" => "g2",
        "attributes" => { "name" => "Old Group", "archived_at" => 1.month.ago.iso8601 },
        "relationships" => { "group_type" => { "data" => nil }, "location" => { "data" => nil } } },
    ], "included" => [
      { "type" => "Location", "id" => "loc1", "attributes" => { "name" => "The Smiths'", "full_formatted_address" => "1 Main St" } },
    ] })
    stub_pco("/groups/g1/memberships", {
      "data" => memberships || [membership("m1", "p1", "leader"), membership("m2", "p2", "member")],
      "included" => [person("p1", "Lee", email: "lee@example.com"), person("p2", "Mo")],
    })
    stub_pco("/groups/g1/events", { "data" => events || [event("e1", 1.week.ago), event("e2", 1.week.from_now)] })
    stub_pco("/events/e1/attendances", {
      "data" => [
        { "type" => "Attendance", "id" => "a1", "attributes" => { "attended" => true, "role" => "leader" },
          "relationships" => { "person" => { "data" => { "type" => "Person", "id" => "p1" } } } },
        { "type" => "Attendance", "id" => "a2", "attributes" => { "attended" => false, "role" => "member" },
          "relationships" => { "person" => { "data" => { "type" => "Person", "id" => "p2" } } } },
      ],
      "included" => [person("p1", "Lee"), person("p2", "Mo")],
    })
    stub_pco("/group_applications", { "data" => applications || [
      { "type" => "GroupApplication", "id" => "app1",
        "attributes" => { "status" => "pending", "applied_at" => 2.days.ago.iso8601, "message" => "Can I join?" },
        "relationships" => { "group" => { "data" => { "type" => "Group", "id" => "g1" } },
                             "person" => { "data" => { "type" => "Person", "id" => "p3" } } } },
    ], "included" => [person("p3", "Ana", email: "ana@example.com")] })
  end

  it "mirrors group types, groups, memberships, meetings, attendance and join requests" do
    stub_full_sync
    described_class.perform_now(church.id)

    expect(church.group_types.sole).to have_attributes(name: "Adult Groups", audience: "adults")
    group = church.groups.find_by!(pco_group_id: "g1")
    expect(group).to have_attributes(name: "Tuesday Night", schedule_text: "Tuesdays at 7pm",
                                     location_name: "The Smiths'", location_address: "1 Main St",
                                     group_type: church.group_types.sole)
    expect(church.groups.find_by!(pco_group_id: "g2").archived_at).to be_present

    leader = church.people.find_by!(pco_person_id: "p1")
    expect(leader.email).to eq("lee@example.com")
    expect(group.memberships.current.leaders.map(&:person)).to eq([leader])
    expect(group.memberships.current.count).to eq(2)

    expect(group.events.order(:starts_at).pluck(:pco_event_id)).to eq(%w[e1 e2])
    past = group.events.find_by!(pco_event_id: "e1")
    expect(past.attendance_synced_at).to be_present
    expect(past.attendances.where(attended: true).map(&:person)).to eq([leader])

    application = church.group_applications.sole
    expect(application).to have_attributes(group: group, message: "Can I join?")
    expect(application.person.email).to eq("ana@example.com")

    expect(church.sync_setting.groups_last_synced_at).to be_present
  end

  it "only syncs memberships and meetings for active groups" do
    stub_full_sync
    described_class.perform_now(church.id)

    expect(a_request(:get, %r{/groups/g2/})).not_to have_been_made
  end

  it "soft-removes what disappeared from PCO and deletes join requests that are no longer pending" do
    stub_full_sync
    described_class.perform_now(church.id)

    stub_full_sync(memberships: [membership("m1", "p1", "leader")], events: [event("e1", 1.week.ago)],
                   applications: [])
    described_class.perform_now(church.id)

    group = church.groups.find_by!(pco_group_id: "g1")
    gone = group.memberships.find_by!(pco_membership_id: "m2")
    expect(gone.left_at).to be_present
    expect(group.memberships.current.count).to eq(1)
    expect(group.events.find_by!(pco_event_id: "e2").removed_at).to be_present
    expect(church.group_applications).to be_empty

    stub_full_sync(groups: [])
    described_class.perform_now(church.id)
    expect(group.reload.removed_at).to be_present
  end

  it "brings a membership back when it reappears" do
    stub_full_sync(memberships: [membership("m1", "p1", "leader")])
    described_class.perform_now(church.id)
    stub_full_sync
    described_class.perform_now(church.id)
    stub_full_sync(memberships: [membership("m1", "p1", "leader")])
    described_class.perform_now(church.id)
    stub_full_sync
    described_class.perform_now(church.id)

    expect(church.group_memberships.find_by!(pco_membership_id: "m2").left_at).to be_nil
  end

  it "records a 403 as missing Groups access instead of failing" do
    stub_pco("/group_types", { "errors" => [] }, status: 403)

    expect { described_class.perform_now(church.id) }.not_to raise_error
    expect(church.reload.sync_setting.groups_access_denied_at).to be_present
  end

  it "clears the missing-access flag after a successful sync" do
    create(:spirely_sync_setting, church: church, groups_access_denied_at: 1.day.ago)
    stub_full_sync
    described_class.perform_now(church.id)

    expect(church.sync_setting.reload.groups_access_denied_at).to be_nil
  end

  it "retries a rate-limited page" do
    stub_full_sync
    stub_request(:get, "#{PCO}/group_types").with(query: hash_including({}))
      .to_return({ status: 429, body: "{}" },
                 { status: 200, body: { "data" => [] }.to_json, headers: { "Content-Type" => "application/json" } })

    expect { described_class.perform_now(church.id) }.not_to raise_error
    expect(church.sync_setting.reload.groups_last_synced_at).to be_present
  end

  it "does nothing for a church without a groups module" do
    church.update!(enabled_modules: ["kidsmin"])
    described_class.perform_now(church.id)

    expect(a_request(:get, /groups\/v2/)).not_to have_been_made
  end
end
