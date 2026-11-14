require "rails_helper"

RSpec.describe Spirely::Family, type: :model do
  describe "validations" do
    it "accepts a valid email" do
      expect(build(:spirely_family, email: "good@example.com")).to be_valid
    end

    it "rejects an invalid email" do
      family = build(:spirely_family, email: "not-an-email")
      expect(family).not_to be_valid
      expect(family.errors[:email]).to be_present
    end

    it "allows a blank email" do
      expect(build(:spirely_family, email: "")).to be_valid
    end
  end

  it "requires a church" do
    expect(build(:spirely_family, church: nil)).not_to be_valid
  end

  it "allows the same account to have a family at two different churches" do
    account = create(:account)
    create(:spirely_family, account: account, church: create(:church))
    second  = build(:spirely_family, account: account, church: create(:church))
    expect(second).to be_valid
  end

  it "prevents the same account having two families at the same church" do
    account = create(:account)
    church  = create(:church)
    create(:spirely_family, account: account, church: church)
    duplicate = build(:spirely_family, account: account, church: church)
    expect(duplicate).not_to be_valid
  end

  describe "#primary_contact_name" do
    it "concatenates first and last name" do
      family = build(:spirely_family, primary_contact_first_name: "Jane", primary_contact_last_name: "Doe")
      expect(family.primary_contact_name).to eq("Jane Doe")
    end

    it "splits a full name on assignment" do
      family = build(:spirely_family)
      family.primary_contact_name = "John Smith"
      expect(family.primary_contact_first_name).to eq("John")
      expect(family.primary_contact_last_name).to eq("Smith")
    end
  end

  describe "#person" do
    it "finds the Spirely::Person sharing the primary contact's pco_person_id" do
      church = create(:church)
      family = create(:spirely_family, church: church, pco_person_id: "pco-parent-1")
      person = create(:spirely_person, church: church, pco_person_id: "pco-parent-1")

      expect(family.person).to eq(person)
    end

    it "is nil when pco_person_id is blank" do
      family = create(:spirely_family, pco_person_id: nil)
      expect(family.person).to be_nil
    end

    it "is nil when no matching Person has synced yet" do
      family = create(:spirely_family, pco_person_id: "pco-parent-unsynced")
      expect(family.person).to be_nil
    end
  end

  describe ".attendance_active / .attendance_inactive" do
    it "counts a family active when a child has checked in within the window" do
      church = create(:church)
      family = create(:spirely_family, church: church)
      create(:spirely_child, family: family, pco_person_id: "pco-kid-1")
      person = create(:spirely_person, church: church, pco_person_id: "pco-kid-1")
      create(:spirely_attendance, person: person, checked_in_at: 3.months.ago)

      expect(Spirely::Family.attendance_active).to include(family)
      expect(Spirely::Family.attendance_inactive).not_to include(family)
    end

    it "counts a family active when the primary contact has checked in within the window" do
      church = create(:church)
      family = create(:spirely_family, church: church, pco_person_id: "pco-parent-1")
      person = create(:spirely_person, church: church, pco_person_id: "pco-parent-1")
      create(:spirely_attendance, person: person, checked_in_at: 1.month.ago)

      expect(Spirely::Family.attendance_active).to include(family)
    end

    it "counts a family inactive when its only check-in is outside the window" do
      church = create(:church)
      family = create(:spirely_family, church: church)
      create(:spirely_child, family: family, pco_person_id: "pco-kid-2")
      person = create(:spirely_person, church: church, pco_person_id: "pco-kid-2")
      create(:spirely_attendance, person: person, checked_in_at: 400.days.ago)

      expect(Spirely::Family.attendance_active).not_to include(family)
      expect(Spirely::Family.attendance_inactive).to include(family)
    end

    it "counts a family inactive when it has no attendance data at all" do
      family = create(:spirely_family)
      create(:spirely_child, family: family)

      expect(Spirely::Family.attendance_active).not_to include(family)
      expect(Spirely::Family.attendance_inactive).to include(family)
    end
  end
end
