class CreateSpirelyTasks < ActiveRecord::Migration[7.2]
  def change
    # v1 scope (5ST-6): the Spirely-native Task entity only — no PCO
    # Workflow sync columns yet (synced_workflow_id etc.), since whether
    # every Task gets a PCO card or only ones explicitly linked is still
    # an open design question, deferred to that follow-up.
    create_table :spirely_tasks do |t|
      t.bigint   :church_id, null: false
      t.string   :title, null: false
      t.text     :description
      t.string   :status, default: "not_started", null: false
      t.date     :due_date
      t.bigint   :assignee_membership_id
      t.bigint   :created_by_membership_id
      t.timestamps
    end

    add_index :spirely_tasks, :church_id
    add_index :spirely_tasks, :assignee_membership_id
    add_index :spirely_tasks, [:church_id, :status]
    add_foreign_key :spirely_tasks, :churches
    add_foreign_key :spirely_tasks, :memberships, column: :assignee_membership_id, on_delete: :nullify
    add_foreign_key :spirely_tasks, :memberships, column: :created_by_membership_id, on_delete: :nullify
  end
end
