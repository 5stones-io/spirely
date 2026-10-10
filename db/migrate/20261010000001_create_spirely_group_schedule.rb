# Weekly group schedule (Small Groups module, 5ST-55) — who leads and hosts
# each meeting, with accept/decline. Planning Center Groups has no such
# thing, so this is Spirely-only data layered on the synced groups.
class CreateSpirelyGroupSchedule < ActiveRecord::Migration[7.2]
  def change
    # Which jobs this group schedules ("lead" is always on), and a repeat
    # for groups that have no upcoming Planning Center events.
    add_column :spirely_groups, :schedule_jobs, :string, array: true, null: false,
               default: %w[lead host_home refreshments]
    add_column :spirely_groups, :cadence_weekday, :integer          # 0 = Sunday
    add_column :spirely_groups, :cadence_interval_weeks, :integer, null: false, default: 1
    add_column :spirely_groups, :cadence_anchor_on, :date

    # One leader per group can schedule it from My Groups.
    add_column :spirely_group_memberships, :head_leader, :boolean, null: false, default: false
    add_index :spirely_group_memberships, :group_id, unique: true, where: "head_leader",
              name: "index_spirely_group_memberships_one_head_leader"

    create_table :spirely_group_schedule_assignments do |t|
      t.references :church, null: false, foreign_key: true
      t.references :group, null: false, foreign_key: { to_table: :spirely_groups }
      t.date :meets_on, null: false
      t.string :job, null: false                 # lead / host_home / refreshments
      t.references :group_event, foreign_key: { to_table: :spirely_group_events }
      t.references :person, foreign_key: { to_table: :spirely_people }   # nil = open
      t.string :status, null: false, default: "open"   # open/pending/accepted/declined
      t.string :source                           # staff / head_leader / self
      t.references :assigned_by_account, foreign_key: { to_table: :accounts, on_delete: :nullify }
      t.datetime :responded_at
      # Accept/decline link token — only its SHA-256 digest is stored.
      t.string :token_digest
      t.datetime :token_expires_at
      t.datetime :notified_at
      t.string :notify_channels, array: true, null: false, default: []
      t.timestamps
      t.index [:group_id, :meets_on, :job], unique: true, name: "index_spirely_group_schedule_slot"
      t.index :token_digest, unique: true
    end
  end
end
