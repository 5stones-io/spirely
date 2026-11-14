# Feedback and requests (5ST-80): anyone at a church sends feedback, with
# pictures and documents attached; admins work through it in an inbox.
#
# - sender_role is who they were when they sent it (staff, parent, member).
# - The sender's account and family are let go, not deleted, if those are
#   removed: the church keeps what it was told.
# - task is the Task staff made from it, if any.
class CreateSpirelyFeedbacks < ActiveRecord::Migration[7.2]
  def change
    create_table :spirely_feedbacks do |t|
      t.references :church, null: false, foreign_key: true
      t.references :account, foreign_key: { on_delete: :nullify }
      t.references :family, foreign_key: { to_table: :spirely_families, on_delete: :nullify }
      t.references :task, foreign_key: { to_table: :spirely_tasks, on_delete: :nullify }
      t.string :sender_role, null: false
      t.string :category, null: false
      t.string :tone
      t.string :about
      t.text :body, null: false
      t.string :status, null: false, default: "new"
      t.text :staff_note
      t.timestamps
      t.index [:church_id, :status, :created_at]
    end
  end
end
