# Attendance follow-ups for groups and classes (Small Groups, 5ST-53).
# PCO shows who's been missing; it doesn't track who's following up or
# what happened. One open follow-up per person per group at a time.
class CreateSpirelyGroupNudges < ActiveRecord::Migration[7.2]
  def change
    create_table :spirely_group_nudges do |t|
      t.references :church, null: false, foreign_key: true
      t.references :group, null: false, foreign_key: { to_table: :spirely_groups }
      t.references :person, null: false, foreign_key: { to_table: :spirely_people }
      t.string :reason, null: false, default: "attendance_drop"
      # The last meetings considered, oldest first: [{ "date", "attended" }],
      # plus counts — refreshed weekly while the follow-up is open.
      t.jsonb :metrics, null: false, default: {}
      t.references :owner_person, foreign_key: { to_table: :spirely_people, on_delete: :nullify }
      t.datetime :resolved_at
      t.string :resolution                      # contacted / returned / dismissed
      t.references :resolved_by_account, foreign_key: { to_table: :accounts, on_delete: :nullify }
      t.timestamps
      t.index [:group_id, :person_id], unique: true, where: "resolved_at IS NULL",
              name: "index_spirely_group_nudges_one_open_per_person"
    end

    create_table :spirely_group_nudge_notes do |t|
      t.references :church, null: false, foreign_key: true
      t.references :group_nudge, null: false, foreign_key: { to_table: :spirely_group_nudges }
      t.references :author_account, foreign_key: { to_table: :accounts, on_delete: :nullify }
      t.string :author_name                     # snapshot; "Spirely" for automatic entries
      t.text :body
      t.string :outcome                         # set when this entry closed the follow-up
      t.timestamps
    end
  end
end
