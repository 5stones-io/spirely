require "rails_helper"

RSpec.describe Spirely::Person, type: :model do
  it "requires pco_person_id unique per church, not globally" do
    church_a = create(:church, slug: "church-a")
    church_b = create(:church, slug: "church-b")
    create(:spirely_person, church: church_a, pco_person_id: "shared-id")

    expect(build(:spirely_person, church: church_a, pco_person_id: "shared-id")).not_to be_valid
    expect(build(:spirely_person, church: church_b, pco_person_id: "shared-id")).to be_valid
  end

  it "requires first_name" do
    expect(build(:spirely_person, first_name: nil)).not_to be_valid
  end

  describe "#full_name" do
    it "joins first and last name" do
      person = build(:spirely_person, first_name: "Jane", last_name: "Doe")
      expect(person.full_name).to eq("Jane Doe")
    end

    it "handles a missing last name" do
      person = build(:spirely_person, first_name: "Cher", last_name: nil)
      expect(person.full_name).to eq("Cher")
    end
  end

  describe "#assessment_completed?" do
    it "is true once a result is present" do
      expect(build(:spirely_person, assessment_result: "Encourager")).to be_assessment_completed
    end

    it "is false with no result" do
      expect(build(:spirely_person, assessment_result: nil)).not_to be_assessment_completed
    end
  end
end
