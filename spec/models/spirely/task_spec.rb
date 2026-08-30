require "rails_helper"

RSpec.describe Spirely::Task, type: :model do
  describe "validations" do
    it "is valid with required fields" do
      expect(build(:spirely_task)).to be_valid
    end

    it "requires a title" do
      expect(build(:spirely_task, title: "")).not_to be_valid
    end

    it "rejects a status outside the canonical set" do
      expect(build(:spirely_task, status: "someday")).not_to be_valid
    end
  end

  describe "defaults" do
    it "defaults status to not_started on create" do
      task = create(:spirely_task, status: nil)
      expect(task.status).to eq("not_started")
    end

    it "leaves an explicitly-set status alone" do
      task = create(:spirely_task, status: "in_progress")
      expect(task.status).to eq("in_progress")
    end
  end

  describe "#complete?" do
    it "is true only for the complete status" do
      expect(build(:spirely_task, status: "complete")).to be_complete
      expect(build(:spirely_task, status: "in_progress")).not_to be_complete
    end
  end

  describe ".open" do
    it "excludes complete tasks" do
      church = create(:church)
      open_task = create(:spirely_task, church: church, status: "in_progress")
      create(:spirely_task, church: church, status: "complete")

      expect(church.tasks.open).to contain_exactly(open_task)
    end
  end
end
