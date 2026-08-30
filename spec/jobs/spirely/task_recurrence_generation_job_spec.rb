require "rails_helper"

RSpec.describe Spirely::TaskRecurrenceGenerationJob, type: :job do
  it "generates the next occurrence for an overdue absolute-recurrence task" do
    task = create(:spirely_task, recurrence_rule: "monthly", recurrence_mode: "absolute",
                                  due_date: 1.day.ago.to_date)

    expect { described_class.new.perform }.to change(Spirely::Task, :count).by(1)
    expect(task.reload.next_occurrence_generated_at).not_to be_nil
  end

  it "ignores an absolute-recurrence task not yet due" do
    create(:spirely_task, recurrence_rule: "monthly", recurrence_mode: "absolute",
                           due_date: 1.day.from_now.to_date)

    expect { described_class.new.perform }.not_to change(Spirely::Task, :count)
  end

  it "ignores relative-recurrence tasks entirely, even if overdue" do
    create(:spirely_task, recurrence_rule: "weekly", recurrence_mode: "relative",
                           due_date: 1.day.ago.to_date, status: "not_started")

    expect { described_class.new.perform }.not_to change(Spirely::Task, :count)
  end

  it "ignores non-recurring overdue tasks" do
    create(:spirely_task, recurrence_rule: "none", due_date: 1.day.ago.to_date)

    expect { described_class.new.perform }.not_to change(Spirely::Task, :count)
  end

  it "doesn't regenerate a task that's already been swept once" do
    create(:spirely_task, recurrence_rule: "monthly", recurrence_mode: "absolute",
                           due_date: 1.day.ago.to_date, next_occurrence_generated_at: 1.hour.ago)

    expect { described_class.new.perform }.not_to change(Spirely::Task, :count)
  end
end
