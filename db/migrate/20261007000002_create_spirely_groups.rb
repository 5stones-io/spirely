# Read-only mirror of Planning Center Groups (Small Groups module, 5ST-51).
# Core data shared by any module that uses groups — Small Groups today,
# Kids Ministry's children's groups later — so these tables aren't owned
# by one module. Rows removed in PCO are soft-removed (removed_at /
# left_at) rather than deleted: group health and drop-off checks need the
# history. Join requests are the exception (a transient queue).
class CreateSpirelyGroups < ActiveRecord::Migration[7.2]
  def change
    create_table :spirely_group_types do |t|
      t.references :church, null: false, foreign_key: true
      t.string :pco_group_type_id, null: false
      t.string :name, null: false
      t.string :color
      # "adults" (default) or "children" — set by staff in Settings, never
      # from PCO. Every group of this type inherits it.
      t.string :audience, null: false, default: "adults"
      t.datetime :removed_at
      t.timestamps
      t.index [:church_id, :pco_group_type_id], unique: true
    end

    create_table :spirely_groups do |t|
      t.references :church, null: false, foreign_key: true
      t.references :group_type, foreign_key: { to_table: :spirely_group_types }
      t.string :pco_group_id, null: false
      t.string :name, null: false
      t.text :description
      # PCO's free-text schedule ("Tuesdays at 7pm") — display only.
      t.string :schedule_text
      t.string :location_name
      t.string :location_address
      t.integer :memberships_count
      t.string :church_center_url
      t.datetime :archived_at
      t.datetime :removed_at
      t.datetime :pco_last_synced_at
      t.timestamps
      t.index [:church_id, :pco_group_id], unique: true
    end

    create_table :spirely_group_memberships do |t|
      t.references :church, null: false, foreign_key: true
      t.references :group, null: false, foreign_key: { to_table: :spirely_groups }
      t.references :person, null: false, foreign_key: { to_table: :spirely_people }
      t.string :pco_membership_id, null: false
      t.string :role, null: false, default: "member"
      t.datetime :joined_at
      t.datetime :left_at
      t.timestamps
      t.index [:church_id, :pco_membership_id], unique: true
    end

    create_table :spirely_group_events do |t|
      t.references :church, null: false, foreign_key: true
      t.references :group, null: false, foreign_key: { to_table: :spirely_groups }
      t.string :pco_event_id, null: false
      t.string :name
      t.datetime :starts_at, null: false
      t.datetime :ends_at
      t.boolean :canceled, null: false, default: false
      t.datetime :removed_at
      t.datetime :attendance_synced_at
      t.timestamps
      t.index [:church_id, :pco_event_id], unique: true
      t.index [:group_id, :starts_at]
    end

    create_table :spirely_group_attendances do |t|
      t.references :church, null: false, foreign_key: true
      t.references :group_event, null: false, foreign_key: { to_table: :spirely_group_events }
      t.references :person, null: false, foreign_key: { to_table: :spirely_people }
      t.boolean :attended, null: false, default: false
      t.string :role
      t.timestamps
      t.index [:group_event_id, :person_id], unique: true
    end

    create_table :spirely_group_applications do |t|
      t.references :church, null: false, foreign_key: true
      t.references :group, null: false, foreign_key: { to_table: :spirely_groups }
      t.references :person, null: false, foreign_key: { to_table: :spirely_people }
      t.string :pco_application_id, null: false
      t.string :status, null: false
      t.datetime :applied_at
      t.text :message
      t.timestamps
      t.index [:church_id, :pco_application_id], unique: true
    end

    # Groups sync bookkeeping. groups_access_denied_at is set when PCO
    # answers a groups request with 403 (an OAuth connection made before
    # the `groups` scope existed, or a PAT user without Groups access) and
    # cleared on the next successful sync — Settings shows a "reconnect"
    # notice from it.
    add_column :spirely_sync_settings, :groups_last_synced_at, :datetime
    add_column :spirely_sync_settings, :groups_access_denied_at, :datetime
  end
end
