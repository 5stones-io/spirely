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
