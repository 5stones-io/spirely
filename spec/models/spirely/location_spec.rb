require "rails_helper"

RSpec.describe Spirely::Location, type: :model do
  describe "validations" do
    it "is valid with required fields" do
      expect(build(:spirely_location)).to be_valid
    end

    it "requires a pco_location_id" do
      expect(build(:spirely_location, pco_location_id: nil)).not_to be_valid
    end

    it "requires a name" do
      expect(build(:spirely_location, name: nil)).not_to be_valid
    end

    it "requires pco_location_id to be unique within a church" do
      church = create(:church)
      create(:spirely_location, church: church, pco_location_id: "loc-1")
      dup = build(:spirely_location, church: church, pco_location_id: "loc-1")
      expect(dup).not_to be_valid
    end

    it "allows the same pco_location_id across different churches" do
      create(:spirely_location, pco_location_id: "loc-1")
      other_church_location = build(:spirely_location, pco_location_id: "loc-1")
      expect(other_church_location).to be_valid
    end
  end

  describe "attendances" do
    it "nullifies attendances' location on destroy rather than destroying them" do
      location   = create(:spirely_location)
      attendance = create(:spirely_attendance, church: location.church, location: location)

      location.destroy!

      expect(attendance.reload.location_id).to be_nil
    end
  end
end
