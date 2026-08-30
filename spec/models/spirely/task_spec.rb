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

    it "rejects a recurrence_rule outside the canonical set" do
      expect(build(:spirely_task, recurrence_rule: "yearly")).not_to be_valid
    end

    it "requires a recurrence_mode when recurring" do
      expect(build(:spirely_task, recurrence_rule: "weekly", recurrence_mode: nil)).not_to be_valid
    end

    it "rejects a recurrence_mode when not recurring" do
      expect(build(:spirely_task, recurrence_rule: "none", recurrence_mode: "relative")).not_to be_valid
    end

    it "requires a positive recurrence_interval for every_n_days" do
      expect(build(:spirely_task, recurrence_rule: "every_n_days", recurrence_mode: "relative", recurrence_interval: nil)).not_to be_valid
      expect(build(:spirely_task, recurrence_rule: "every_n_days", recurrence_mode: "relative", recurrence_interval: 0)).not_to be_valid
      expect(build(:spirely_task, recurrence_rule: "every_n_days", recurrence_mode: "relative", recurrence_interval: 3)).to be_valid
    end

    it "rejects a recurrence_interval for any rule other than every_n_days" do
      expect(build(:spirely_task, recurrence_rule: "weekly", recurrence_mode: "relative", recurrence_interval: 3)).not_to be_valid
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

    it "defaults recurrence_rule to none" do
      expect(create(:spirely_task).recurrence_rule).to eq("none")
    end
  end

  describe "#complete?" do
    it "is true only for the complete status" do
      expect(build(:spirely_task, status: "complete")).to be_complete
      expect(build(:spirely_task, status: "in_progress")).not_to be_complete
    end
  end

  describe "#recurring?" do
    it "is false for recurrence_rule none" do
      expect(build(:spirely_task, recurrence_rule: "none")).not_to be_recurring
    end

    it "is true for any other recurrence_rule" do
      expect(build(:spirely_task, recurrence_rule: "weekly", recurrence_mode: "relative")).to be_recurring
    end
  end

  describe "completed_at tracking" do
    it "sets completed_at when status transitions to complete" do
      task = create(:spirely_task, status: "not_started")
      expect { task.update!(status: "complete") }.to change { task.completed_at }.from(nil)
    end

    it "clears completed_at when reopened" do
      task = create(:spirely_task, status: "complete")
      expect(task.completed_at).not_to be_nil
      task.update!(status: "not_started")
      expect(task.completed_at).to be_nil
    end

    it "doesn't touch completed_at on unrelated updates" do
      task = create(:spirely_task, status: "complete")
      original = task.completed_at
      task.update!(title: "Renamed")
      expect(task.completed_at).to eq(original)
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
