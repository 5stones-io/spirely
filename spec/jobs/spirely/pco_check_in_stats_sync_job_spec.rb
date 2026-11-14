require "rails_helper"

RSpec.describe Spirely::PcoCheckInStatsSyncJob do
  before { Spirely.configuration.encryption_key = SecureRandom.hex(32) }

  let(:church) { create(:church) }

  let!(:integration) do
    create(:spirely_church_integration, church: church, access_token: "tok",
                                         pco_client_id: "id", pco_client_secret: "sec")
  end

  def pco_person(id, count:, last: nil, first_name: "Kid")
    { id: id, type: "Person",
      attributes: { first_name: first_name, last_name: "Q", child: true, birthdate: "2018-04-01",
                    check_in_count: count, last_checked_in_at: last } }
  end

  def stub_page(offset, people, next_link: true)
    stub_request(:get, "https://api.planningcenteronline.com/check-ins/v2/people")
      .with(query: hash_including("order" => "-check_in_count", "offset" => offset.to_s, "per_page" => "100"))
      .to_return(status: 200,
                 body: { data: people, links: next_link ? { next: "https://api.planningcenteronline.com/check-ins/v2/people?offset=#{offset + 100}" } : {} }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  it "does nothing when the church has no connected PCO integration" do
    integration.update!(access_token: nil)

    described_class.new.perform(church.id)

    expect(WebMock).not_to have_requested(:get, /planningcenteronline/)
  end

  it "creates a Person with PCO's all-time stats for a known child who has no local Person yet" do
    family = create(:spirely_family, church: church)
    create(:spirely_child, family: family, pco_person_id: "kid-1")
    stub_page(0, [pco_person("kid-1", count: 40, last: "2025-11-02T14:00:00Z")], next_link: false)

    described_class.new.perform(church.id)

    person = church.people.find_by(pco_person_id: "kid-1")
    expect(person).to have_attributes(check_in_count: 40, first_name: "Kid", email: nil)
    expect(person.last_checked_in_at).to eq(Time.zone.parse("2025-11-02T14:00:00Z"))
  end

  it "refreshes stats on an existing Person even if they aren't in any family" do
    volunteer = create(:spirely_person, church: church, pco_person_id: "vol-1", first_name: "Val")
    stub_page(0, [pco_person("vol-1", count: 7, last: "2026-01-01T10:00:00Z")], next_link: false)

    described_class.new.perform(church.id)

    expect(volunteer.reload).to have_attributes(check_in_count: 7, first_name: "Val")
  end

  it "does not create a Person for a PCO attendee this church has no family record of" do
    stub_page(0, [pco_person("stranger", count: 3, last: "2026-01-01T10:00:00Z")], next_link: false)

    described_class.new.perform(church.id)

    expect(church.people.where(pco_person_id: "stranger")).to be_empty
  end

  it "counts a guardian as known" do
    family = create(:spirely_family, church: church)
    create(:spirely_guardian, family: family, pco_person_id: "g-1")
    stub_page(0, [pco_person("g-1", count: 2, last: "2026-02-01T10:00:00Z")], next_link: false)

    described_class.new.perform(church.id)

    expect(church.people.find_by(pco_person_id: "g-1")&.check_in_count).to eq(2)
  end

  it "pages until the first person with zero check-ins, then stops" do
    family = create(:spirely_family, church: church)
    create(:spirely_child, family: family, pco_person_id: "kid-150")
    create(:spirely_child, family: family, pco_person_id: "never")

    first_page  = (1..100).map { |i| pco_person("p-#{i}", count: 500 - i) }
    second_page = [pco_person("kid-150", count: 5, last: "2026-03-01T10:00:00Z"), pco_person("never", count: 0)]
    stub_page(0, first_page)
    stub_page(100, second_page)

    described_class.new.perform(church.id)

    expect(church.people.find_by(pco_person_id: "kid-150")&.check_in_count).to eq(5)
    expect(church.people.where(pco_person_id: "never")).to be_empty
    expect(WebMock).not_to have_requested(:get, /check-ins\/v2\/people/).with(query: hash_including("offset" => "200"))
  end

  it "waits and retries a page once on a 429" do
    family = create(:spirely_family, church: church)
    create(:spirely_child, family: family, pco_person_id: "kid-1")
    allow_any_instance_of(described_class).to receive(:sleep)

    stub_request(:get, "https://api.planningcenteronline.com/check-ins/v2/people")
      .with(query: hash_including("offset" => "0"))
      .to_return({ status: 429, body: "{}" },
                 { status: 200, body: { data: [pco_person("kid-1", count: 1, last: "2026-03-01T10:00:00Z")], links: {} }.to_json,
                   headers: { "Content-Type" => "application/json" } })

    described_class.new.perform(church.id)

    expect(church.people.find_by(pco_person_id: "kid-1")&.check_in_count).to eq(1)
  end
end
