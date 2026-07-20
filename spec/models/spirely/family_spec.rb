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

  describe "#primary_contact_name" do
    it "concatenates first and last name" do
      family = build(:spirely_family,
        primary_contact_first_name: "Jane",
        primary_contact_last_name: "Doe")
      expect(family.primary_contact_name).to eq("Jane Doe")
    end

    it "splits a full name on assignment" do
      family = build(:spirely_family)
      family.primary_contact_name = "John Smith"
      expect(family.primary_contact_first_name).to eq("John")
      expect(family.primary_contact_last_name).to eq("Smith")
    end
  end
end
