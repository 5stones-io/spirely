class AddRecurrenceToSpirelyTasks < ActiveRecord::Migration[7.2]
  def change
    # 5ST-7 — small enum + interval, not full RRULE (Chad's call): covers
    # daily/weekly/biweekly/monthly/every_n_days, which is every pattern a
    # church staff task realistically needs. recurrence_interval is only
    # meaningful for "every_n_days" (the N); every other rule has a fixed
    # cadence baked into its name.
    #
    # recurrence_mode distinguishes *when* the next occurrence is due:
    # "relative" (N days/weeks after this one is actually completed —
    # Todoist's default) vs "absolute" (a fixed calendar cadence off the
    # current due_date, regardless of whether/when this one gets done —
    # "submit the report on the 1st no matter what"). Both are real
    # patterns church staff need (Chad's own example), so both are
    # supported rather than picking one.
    add_column :spirely_tasks, :recurrence_rule, :string, default: "none", null: false
    add_column :spirely_tasks, :recurrence_interval, :integer
    add_column :spirely_tasks, :recurrence_mode, :string

    # Links every generated occurrence of the same recurring task
    # together — nil for a one-off task. Assigned (SecureRandom.uuid) the
    # first time a recurring task actually generates its next occurrence,
    # not at creation time, so a task that's recurring but never
    # completes/passes due never gets a pointless series id.
    add_column :spirely_tasks, :recurrence_series_id, :uuid

    # completed_at didn't exist before this — Task only tracked
    # completion via status: "complete", no timestamp. Needed as the
    # anchor date for relative recurrence's "N days after completion";
    # generally useful metadata for a task regardless of recurrence.
    add_column :spirely_tasks, :completed_at, :datetime

    # Idempotency guard — without this, a completion webhook retry or the
    # absolute-recurrence sweep job running twice before the next due
    # date rolls over would each spawn their own next occurrence.
    add_column :spirely_tasks, :next_occurrence_generated_at, :datetime

    add_index :spirely_tasks, :recurrence_series_id
    add_index :spirely_tasks, [:recurrence_mode, :next_occurrence_generated_at, :due_date],
              name: "index_spirely_tasks_on_absolute_recurrence_sweep"
  end
end
