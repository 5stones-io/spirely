require "rails_helper"

RSpec.describe Spirely::TaskRecurrenceGenerator do
  describe ".call" do
    it "does nothing for a non-recurring task" do
      task = create(:spirely_task, recurrence_rule: "none")
      expect { described_class.call(task) }.not_to change(Spirely::Task, :count)
    end

    it "does nothing if next_occurrence_generated_at is already set (idempotency guard)" do
      task = create(:spirely_task, recurrence_rule: "weekly", recurrence_mode: "relative",
                                    status: "complete", next_occurrence_generated_at: 1.hour.ago)
      expect { described_class.call(task) }.not_to change(Spirely::Task, :count)
    end

    it "does nothing for relative recurrence that hasn't been completed yet" do
      task = create(:spirely_task, recurrence_rule: "weekly", recurrence_mode: "relative", status: "not_started")
      expect { described_class.call(task) }.not_to change(Spirely::Task, :count)
    end

    it "generates the next occurrence for relative recurrence, due N after completed_at" do
      completed = Time.zone.parse("2026-09-01 10:00:00")
      task = create(:spirely_task, title: "Water the plants", recurrence_rule: "every_n_days",
                                    recurrence_mode: "relative", recurrence_interval: 3,
                                    status: "complete", completed_at: completed)

      expect { described_class.call(task) }.to change(Spirely::Task, :count).by(1)

      next_task = Spirely::Task.order(:id).last
      expect(next_task.title).to eq("Water the plants")
      expect(next_task.due_date).to eq(completed.to_date + 3.days)
      expect(next_task.status).to eq("not_started")
      expect(next_task.recurrence_rule).to eq("every_n_days")
      expect(next_task.recurrence_interval).to eq(3)
    end

    it "generates the next occurrence for absolute recurrence, due N after the current due_date, regardless of completion" do
      task = create(:spirely_task, recurrence_rule: "monthly", recurrence_mode: "absolute",
                                    due_date: Date.new(2026, 9, 1), status: "not_started")

      expect { described_class.call(task) }.to change(Spirely::Task, :count).by(1)

      next_task = Spirely::Task.order(:id).last
      expect(next_task.due_date).to eq(Date.new(2026, 10, 1))
    end

    it "carries the assignee and created_by forward" do
      church  = create(:church)
      account = create(:account)
      membership = create(:membership, :admin, church: church, account: account)
      task = create(:spirely_task, church: church, recurrence_rule: "daily", recurrence_mode: "absolute",
                                    due_date: Date.current, assignee: membership, created_by: membership)

      described_class.call(task)
      next_task = Spirely::Task.order(:id).last
      expect(next_task.assignee_membership_id).to eq(membership.id)
      expect(next_task.created_by_membership_id).to eq(membership.id)
    end

    it "assigns a shared recurrence_series_id across occurrences, generated once" do
      task = create(:spirely_task, recurrence_rule: "daily", recurrence_mode: "absolute", due_date: Date.current)
      expect(task.recurrence_series_id).to be_nil

      described_class.call(task)
      task.reload
      expect(task.recurrence_series_id).not_to be_nil

      next_task = Spirely::Task.order(:id).last
      expect(next_task.recurrence_series_id).to eq(task.recurrence_series_id)
    end

    it "marks the source task's next_occurrence_generated_at" do
      task = create(:spirely_task, recurrence_rule: "daily", recurrence_mode: "absolute", due_date: Date.current)
      described_class.call(task)
      expect(task.reload.next_occurrence_generated_at).not_to be_nil
    end
  end

  describe ".next_due_date_for" do
    anchor = Date.new(2026, 1, 15)

    it "computes each fixed-cadence rule correctly" do
      expect(described_class.next_due_date_for("daily", nil, anchor)).to eq(Date.new(2026, 1, 16))
      expect(described_class.next_due_date_for("weekly", nil, anchor)).to eq(Date.new(2026, 1, 22))
      expect(described_class.next_due_date_for("biweekly", nil, anchor)).to eq(Date.new(2026, 1, 29))
      expect(described_class.next_due_date_for("monthly", nil, anchor)).to eq(Date.new(2026, 2, 15))
    end

    it "computes every_n_days using the interval" do
      expect(described_class.next_due_date_for("every_n_days", 5, anchor)).to eq(Date.new(2026, 1, 20))
    end

    it "raises for a non-recurring rule" do
      expect { described_class.next_due_date_for("none", nil, anchor) }.to raise_error(ArgumentError)
    end
  end
end
