require "rails_helper"

RSpec.describe Spirely::Child, type: :model do
  describe "validations" do
    it "is valid with required fields" do
      expect(build(:spirely_child)).to be_valid
    end

    it "requires first_name" do
      expect(build(:spirely_child, first_name: "")).not_to be_valid
    end

    it "requires last_name" do
      expect(build(:spirely_child, last_name: "")).not_to be_valid
    end

    it "rejects grade outside -1..12" do
      expect(build(:spirely_child, grade: 13)).not_to be_valid
      expect(build(:spirely_child, grade: -2)).not_to be_valid
    end

    it "allows -1 (PCO's Pre-K convention)" do
      expect(build(:spirely_child, grade: -1)).to be_valid
    end

    it "allows a nil grade" do
      expect(build(:spirely_child, grade: nil)).to be_valid
    end

    it "rejects an unknown allergen value" do
      child = build(:spirely_child, allergens: ["peanuts", "made_up_allergen"])
      expect(child).not_to be_valid
      expect(child.errors[:allergens].first).to include("made_up_allergen")
    end

    it "accepts a known allergen value" do
      expect(build(:spirely_child, allergens: ["peanuts", "dairy"])).to be_valid
    end
  end

  it "inherits church_id from its family" do
    family = create(:spirely_family)
    child  = create(:spirely_child, family: family)
    expect(child.church_id).to eq(family.church_id)
  end

  describe "#grade=" do
    it "stores integer grades as-is" do
      child = build(:spirely_child, grade: 5)
      expect(child.grade).to eq(5)
    end

    it "parses grade strings" do
      expect(build(:spirely_child, grade: "3rd").grade).to eq(3)
      expect(build(:spirely_child, grade: "K").grade).to eq(0)
      expect(build(:spirely_child, grade: "kindergarten").grade).to eq(0)
      expect(build(:spirely_child, grade: "Pre-K").grade).to eq(-1)
    end
  end

  describe "#age" do
    it "returns nil when birthdate is nil" do
      expect(build(:spirely_child, birthdate: nil).age).to be_nil
    end

    it "calculates the correct age" do
      child = build(:spirely_child, birthdate: 8.years.ago.to_date)
      expect(child.age).to eq(8)
    end
  end

  describe "#full_name" do
    it "returns first and last name" do
      child = build(:spirely_child, first_name: "Sam", last_name: "Smith")
      expect(child.full_name).to eq("Sam Smith")
    end
  end

  describe "#update_medical!" do
    it "sets allergens/allergy_notes and stamps allergy_updated_at, leaving updated_at's own meaning intact" do
      child = create(:spirely_child, allergens: [], allergy_notes: nil, allergy_updated_at: nil)

      travel_to Time.zone.local(2026, 1, 1, 12, 0, 0) do
        child.update_medical!(allergens: ["peanuts"], allergy_notes: "Carries an EpiPen")
      end

      expect(child.reload.allergens).to eq(["peanuts"])
      expect(child.allergy_notes).to eq("Carries an EpiPen")
      expect(child.allergy_updated_at).to eq(Time.zone.local(2026, 1, 1, 12, 0, 0))
    end
  end

  describe "#allergy_summary" do
    it "combines allergen labels and free-text notes" do
      child = build(:spirely_child, allergens: ["peanuts", "tree_nuts"], allergy_notes: "Carries an EpiPen")
      expect(child.allergy_summary).to eq("Peanuts, Tree Nuts — Carries an EpiPen")
    end

    it "is just the allergen labels when there's no free-text note" do
      child = build(:spirely_child, allergens: ["dairy"], allergy_notes: nil)
      expect(child.allergy_summary).to eq("Dairy/Milk")
    end

    it "is just the free-text note when there are no structured allergens" do
      child = build(:spirely_child, allergens: [], allergy_notes: "Gets nosebleeds easily")
      expect(child.allergy_summary).to eq("Gets nosebleeds easily")
    end

    it "is nil when neither is set" do
      child = build(:spirely_child, allergens: [], allergy_notes: nil)
      expect(child.allergy_summary).to be_nil
    end
  end

  describe "#person" do
    it "finds the Spirely::Person sharing this child's pco_person_id" do
      church = create(:church)
      family = create(:spirely_family, church: church)
      child  = create(:spirely_child, family: family, pco_person_id: "pco-kid-1")
      person = create(:spirely_person, church: church, pco_person_id: "pco-kid-1")

      expect(child.person).to eq(person)
    end

    it "is nil when pco_person_id is blank" do
      child = create(:spirely_child, pco_person_id: nil)
      expect(child.person).to be_nil
    end

    it "is nil when no matching Person has synced yet" do
      child = create(:spirely_child, pco_person_id: "pco-kid-unsynced")
      expect(child.person).to be_nil
    end

    it "does not cross-contaminate a different church's Person with the same pco_person_id" do
      church_a = create(:church, slug: "church-a")
      church_b = create(:church, slug: "church-b")
      family   = create(:spirely_family, church: church_a)
      child    = create(:spirely_child, family: family, pco_person_id: "shared-id")
      create(:spirely_person, church: church_b, pco_person_id: "shared-id")

      expect(child.person).to be_nil
    end
  end

  describe "ministry interests" do
    it "defaults to no interests" do
      expect(build(:spirely_child).ministry_interests).to eq([])
    end

    it "rejects values outside MINISTRY_INTEREST_LABELS" do
      child = build(:spirely_child, ministry_interests: %w[puppets juggling])
      expect(child).not_to be_valid
      expect(child.errors[:ministry_interests].first).to include("juggling")
    end

    it "rejects an unknown updated_by_role" do
      expect(build(:spirely_child, ministry_interests_updated_by_role: "volunteer")).not_to be_valid
    end

    describe "#update_ministry_interests!" do
      it "stores picks de-duplicated in canonical order and stamps who/when" do
        child  = create(:spirely_child)
        parent = create(:account, first_name: "Sarah", last_name: "Johnson")

        child.update_ministry_interests!(ministry_interests: %w[drama puppets drama arts_and_crafts],
                                         updated_by: parent, updated_by_role: "parent")

        child.reload
        expect(child.ministry_interests).to eq(%w[arts_and_crafts puppets drama])
        expect(child.ministry_interests_updated_at).to be_within(5.seconds).of(Time.current)
        expect(child.ministry_interests_updated_by).to eq(parent)
        expect(child.ministry_interests_updated_by_role).to eq("parent")
        expect(child.ministry_interests_updated_by_name).to eq("Sarah Johnson")
      end

      it "allows every interest at once (no cap)" do
        child = create(:spirely_child)
        child.update_ministry_interests!(ministry_interests: Spirely::Child::MINISTRY_INTEREST_LABELS.keys,
                                         updated_by: nil, updated_by_role: "staff")
        expect(child.reload.ministry_interests.size).to eq(7)
      end

      it "raises and leaves the record unchanged on an unknown value" do
        child = create(:spirely_child)
        expect {
          child.update_ministry_interests!(ministry_interests: %w[juggling], updated_by: nil, updated_by_role: "parent")
        }.to raise_error(ActiveRecord::RecordInvalid)
        expect(child.reload.ministry_interests).to eq([])
      end
    end

    describe "#ministry_interests_updated_by_name" do
      it "falls back to email when the account has no name" do
        account = create(:account, first_name: nil, last_name: nil, email: "parent@example.com")
        child = build(:spirely_child, ministry_interests_updated_by: account)
        expect(child.ministry_interests_updated_by_name).to eq("parent@example.com")
      end

      it "is nil when nobody has updated interests yet" do
        expect(build(:spirely_child).ministry_interests_updated_by_name).to be_nil
      end
    end
  end
end
