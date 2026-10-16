require "rails_helper"

RSpec.describe Spirely::Kudos do
  let(:church) { create(:church, enabled_modules: ["kudos"]) }
  let(:kudos)  { described_class.new(church) }
  let(:admin)  { create(:account, first_name: "Pastor", last_name: "Mike") }
  let(:person) { create(:spirely_person, church: church, first_name: "Sarah", pco_person_id: "p1") }

  def entry(points, **attrs)
    church.points_entries.create!(person: person, points: points, source: "manual", occurred_on: Date.current, **attrs)
  end

  describe "#totals" do
    it "sums the ledger into balance, earned and deducted" do
      entry(100)
      entry(50)
      entry(-30)
      expect(kudos.totals(person)).to eq(balance: 120, earned: 150, deducted: 30)
    end

    it "is all zero for someone with no Person yet" do
      expect(kudos.totals(nil)).to eq(balance: 0, earned: 0, deducted: 0)
    end
  end

  describe "ledger idempotency" do
    it "allows one entry per source record per person" do
      entry(10, source: "checkin", source_type: "Spirely::Attendance", source_id: 7)
      expect { entry(10, source: "checkin", source_type: "Spirely::Attendance", source_id: 7) }
        .to raise_error(ActiveRecord::RecordInvalid)
      expect(church.points_entries.count).to eq(1)
    end

    it "still allows any number of hand-entered entries" do
      2.times { entry(5) }
      expect(church.points_entries.count).to eq(2)
    end
  end

  describe "#award!" do
    it "awards points with a reason and the staff member's name" do
      e = kudos.award!(pco_person_id: person.pco_person_id, points: 50, note: "Helped clean up", by_account: admin)
      expect(e).to have_attributes(points: 50, source: "manual", note: "Helped clean up", awarded_by_name: "Pastor Mike")
      expect(kudos.totals(person)[:balance]).to eq(50)
    end

    it "deducts, but not below zero" do
      entry(20)
      kudos.award!(pco_person_id: "p1", points: -20, note: "Entered twice", by_account: admin)
      expect { kudos.award!(pco_person_id: "p1", points: -1, note: "Oops", by_account: admin) }
        .to raise_error(Spirely::Kudos::Error, /only has 0 points/)
    end

    it "requires a reason and a non-zero whole number" do
      expect { kudos.award!(pco_person_id: "p1", points: 10, note: " ", by_account: admin) }.to raise_error(Spirely::Kudos::Error)
      expect { kudos.award!(pco_person_id: "p1", points: 0, note: "x", by_account: admin) }.to raise_error(Spirely::Kudos::Error)
      expect { kudos.award!(pco_person_id: "p1", points: "1.5", note: "x", by_account: admin) }.to raise_error(Spirely::Kudos::Error)
    end

    it "creates the Person for a kid who's only on a family record so far" do
      family = create(:spirely_family, church: church, family_name: "Johnson")
      create(:spirely_child, family: family, first_name: "Emma", last_name: "Johnson", pco_person_id: "k1")

      kudos.award!(pco_person_id: "k1", points: 25, note: "Brought a friend", by_account: admin)

      created = church.people.find_by!(pco_person_id: "k1")
      expect(created).to have_attributes(first_name: "Emma", child: true)
    end

    it "won't award to someone from another church" do
      other = create(:spirely_person, pco_person_id: "x1")
      expect { kudos.award!(pco_person_id: other.pco_person_id, points: 5, note: "x", by_account: admin) }
        .to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "#recipients" do
    it "finds people across synced people and family records, once each" do
      person
      family = create(:spirely_family, church: church, family_name: "Mitchell", pco_person_id: "p1",
                                       primary_contact_first_name: "Sarah", primary_contact_last_name: "Mitchell")
      create(:spirely_guardian, family: family, first_name: "Sam", last_name: "Mitchell", pco_person_id: "g1")

      found = kudos.recipients(query: "mitch")
      expect(found.map(&:pco_person_id)).to contain_exactly("p1", "g1")
      expect(found.find { |r| r.pco_person_id == "p1" }).to have_attributes(person: person, family: family)
    end
  end

  describe "#history" do
    it "lists newest first with the balance after each entry" do
      entry(100, occurred_on: 3.days.ago.to_date)
      entry(-20, occurred_on: 2.days.ago.to_date)
      entry(40, occurred_on: 1.day.ago.to_date)

      expect(kudos.history(person).map { |e| [e.points, e.balance_after] }).to eq([[40, 120], [-20, 80], [100, 100]])
    end
  end

  describe Spirely::KudosSetting do
    it "starts earning today by default" do
      expect(described_class.for(church).earning_starts_on).to eq(Spirely::ChurchTime.today(church))
      expect(described_class.for(church)).to eq(church.reload.kudos_setting)
    end
  end
end
