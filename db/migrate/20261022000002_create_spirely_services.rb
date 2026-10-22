# Kudos module, phase 3 (5ST-62): a read-only mirror of Planning Center
# Services — service types, plans, plan times and who was scheduled — so
# people earn points for time served. Synced by PcoServicesSyncJob.
class CreateSpirelyServices < ActiveRecord::Migration[7.2]
  def change
    create_table :spirely_service_types do |t|
      t.references :church, null: false, foreign_key: true
      t.string :pco_service_type_id, null: false
      t.string :name, null: false
      t.datetime :removed_at
      t.timestamps
      t.index [:church_id, :pco_service_type_id], unique: true
    end

    create_table :spirely_service_plans do |t|
      t.references :church, null: false, foreign_key: true
      t.references :service_type, null: false, foreign_key: { to_table: :spirely_service_types }
      t.string :pco_plan_id, null: false
      t.string :title
      t.string :series_title
      t.string :dates                           # PCO's own label, e.g. "October 19, 2026"
      t.datetime :sort_date                     # first service time
      t.datetime :ends_at                       # end of the plan's last time; nil until its times are synced
      t.datetime :people_synced_at
      t.datetime :removed_at
      t.timestamps
      t.index [:church_id, :pco_plan_id], unique: true
      t.index [:church_id, :sort_date]
    end

    create_table :spirely_service_plan_times do |t|
      t.references :church, null: false, foreign_key: true
      t.references :plan, null: false, foreign_key: { to_table: :spirely_service_plans, on_delete: :cascade }
      t.string :pco_plan_time_id, null: false
      t.string :name
      t.string :time_type, null: false          # service, rehearsal or other
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.string :team_ids, array: true           # PCO teams scheduled for this time; nil if PCO didn't say
      t.timestamps
      t.index [:plan_id, :pco_plan_time_id], unique: true
    end

    # One row per position someone holds on a plan. Someone on two teams
    # has two rows; their points are per plan, so overlapping times only
    # count once.
    create_table :spirely_service_plan_people do |t|
      t.references :church, null: false, foreign_key: true
      t.references :plan, null: false, foreign_key: { to_table: :spirely_service_plans, on_delete: :cascade }
      t.references :person, null: false, foreign_key: { to_table: :spirely_people }
      t.string :pco_plan_person_id, null: false
      t.string :pco_team_id
      t.string :team_name
      t.string :position_name
      t.string :status, null: false             # C (confirmed), U (unconfirmed) or D (declined)
      t.string :declined_time_ids, array: true, default: [], null: false
      t.timestamps
      t.index [:plan_id, :pco_plan_person_id], unique: true
      t.index [:church_id, :person_id]
    end

    # What a points entry was for, beyond its note — for time served, the
    # plan, roles, times and hours as they were when it was paid.
    add_column :spirely_points_entries, :details, :jsonb

    # Off: only service times count toward hours served.
    add_column :spirely_kudos_settings, :count_rehearsals, :boolean, default: false, null: false

    # Same bookkeeping as the Groups sync: services_access_denied_at is set
    # when PCO answers with 403 (a PAT user without Services access), for
    # Settings' notice.
    add_column :spirely_sync_settings, :services_last_synced_at, :datetime
    add_column :spirely_sync_settings, :services_access_denied_at, :datetime
  end
end
