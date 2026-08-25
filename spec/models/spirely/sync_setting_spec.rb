require "rails_helper"

RSpec.describe Spirely::SyncSetting, type: :model do
  describe "validations" do
    it "rejects an unrecognized conflict_resolution" do
      expect(build(:spirely_sync_setting, conflict_resolution: "bogus")).not_to be_valid
    end

    it "rejects a non-positive sync_frequency_hours" do
      expect(build(:spirely_sync_setting, sync_frequency_hours: 0)).not_to be_valid
    end

    it "is unique per church at the database level" do
      church = create(:church)
      create(:spirely_sync_setting, church: church)
      expect { create(:spirely_sync_setting, church: church) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "#effective_ministry_tag" do
    it "is nil when the column is blank" do
      settings = build(:spirely_sync_setting, pco_ministry_tag: nil)
      expect(settings.effective_ministry_tag).to be_nil
    end

    it "returns the column value when present" do
      settings = build(:spirely_sync_setting, pco_ministry_tag: "db-tag")
      expect(settings.effective_ministry_tag).to eq("db-tag")
    end
  end
end
