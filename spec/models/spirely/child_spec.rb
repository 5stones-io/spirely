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

    it "rejects grade outside 0..12" do
      expect(build(:spirely_child, grade: 13)).not_to be_valid
      expect(build(:spirely_child, grade: -1)).not_to be_valid
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
end
