# Kudos module, phase 1 (5ST-60): the points ledger and per-church
# settings. A person's balance is the sum of their entries — no cached
# column until that's ever slow.
class CreateSpirelyKudos < ActiveRecord::Migration[7.2]
  def change
    create_table :spirely_points_entries do |t|
      t.references :church, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: { to_table: :spirely_people }
      t.integer :points, null: false            # + earned, − spent/deducted
      t.string :source, null: false             # manual, checkin, group_attendance, …
      # Whatever earned it (a check-in, a group attendance, …) — the unique
      # index below keeps a re-run sync from posting the same thing twice.
      t.string :source_type
      t.bigint :source_id
      t.text :note
      t.references :awarded_by_account, foreign_key: { to_table: :accounts, on_delete: :nullify }
      t.string :awarded_by_name                 # snapshot, so history survives a removed account
      t.date :occurred_on, null: false
      t.timestamps
      t.index [:source_type, :source_id, :person_id], unique: true, where: "source_id IS NOT NULL",
              name: "index_spirely_points_entries_one_per_source"
      t.index [:church_id, :occurred_on]
      t.index [:person_id, :occurred_on]
    end

    create_table :spirely_kudos_settings do |t|
      t.references :church, null: false, foreign_key: true, index: { unique: true }
      # Automatic earning (later phases) only counts activity on or after
      # this date, so turning Kudos on doesn't pay out years of history.
      t.date :earning_starts_on, null: false
      t.jsonb :rates, null: false, default: {}  # per-source earning rates, filled in by later phases
      t.timestamps
    end
  end
end
