require "rails_helper"

RSpec.describe Spirely::SyncSetting, type: :model do
  describe ".current" do
    it "creates a singleton with narrowed identity-only defaults" do
      settings = described_class.current
      expect(settings.inbound_people_sync).to be(true)
      expect(settings.outbound_people_sync).to be(false)
      expect(settings.sync_frequency_hours).to eq(6)
      expect(settings.conflict_resolution).to eq("pco_wins")
      expect(settings.auto_sync_enabled).to be(false)
    end
  end

  describe "validations" do
    it "rejects an unrecognized conflict_resolution" do
      expect(build(:spirely_sync_setting, conflict_resolution: "bogus")).not_to be_valid
    end

    it "rejects a non-positive sync_frequency_hours" do
      expect(build(:spirely_sync_setting, sync_frequency_hours: 0)).not_to be_valid
    end
  end

  describe "#effective_ministry_tag" do
    it "falls back to Spirely.configuration.pco_ministry_tag when column is blank" do
      Spirely.configuration.pco_ministry_tag = "configured-tag"
      settings = build(:spirely_sync_setting, pco_ministry_tag: nil)
      expect(settings.effective_ministry_tag).to eq("configured-tag")
    end

    it "prefers the column value when present" do
      settings = build(:spirely_sync_setting, pco_ministry_tag: "db-tag")
      expect(settings.effective_ministry_tag).to eq("db-tag")
    end
  end
end
