require "rails_helper"

RSpec.describe Spirely::Guardian, type: :model do
  it "is valid with required fields" do
    expect(build(:spirely_guardian)).to be_valid
  end

  it "requires first_name" do
    expect(build(:spirely_guardian, first_name: "")).not_to be_valid
  end

  it "allows a blank relationship" do
    expect(build(:spirely_guardian, relationship: "")).to be_valid
  end

  it "rejects an unrecognized relationship" do
    expect(build(:spirely_guardian, relationship: "Neighbor")).not_to be_valid
  end
end
