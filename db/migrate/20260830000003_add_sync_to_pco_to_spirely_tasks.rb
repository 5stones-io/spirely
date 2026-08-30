class AddSyncToPcoToSpirelyTasks < ActiveRecord::Migration[7.2]
  def change
    # Answers 5ST-6's own open design question ("should every Task have
    # a PCO Workflow card, or only ones explicitly linked?") with a plain
    # toggle rather than inferring it from a synced_workflow_id's
    # presence: Chad's ask — checked by default for a task that
    # originates FROM a PCO Workflow card, unchecked by default for one
    # created natively in Spirely. Defaults to `false` here because the
    # only task-creation path that exists today (TasksController#create,
    # a staff member in the app) is the Spirely-native one; a future PCO
    # Workflow import path (not built yet) is expected to explicitly set
    # this `true` for whatever it creates, not rely on this column
    # default. Independent of recurrence — carried forward as plain data
    # by Spirely::TaskRecurrenceGenerator, not derived.
    #
    # Deliberately just a boolean gate, not the actual sync engine itself
    # — no PCO Workflow card is created/updated when this is set yet
    # (append-only notes sync, assignee last-write-wins, status
    # map_status_in/out are still the real, un-built work flagged in
    # 5ST-6's own description).
    add_column :spirely_tasks, :sync_to_pco, :boolean, default: false, null: false
  end
end
