class CreateSpirelySyncSettings < ActiveRecord::Migration[7.2]
  def change
    create_table :spirely_sync_settings do |t|
      t.bigint   :church_id, null: false
      t.boolean  :inbound_people_sync, default: true, null: false
      t.boolean  :outbound_people_sync, default: false, null: false
      t.integer  :sync_frequency_hours, default: 6, null: false
      t.string   :conflict_resolution, default: "pco_wins", null: false
      t.datetime :last_synced_at
      t.string   :pco_ministry_tag
      t.boolean  :auto_sync_enabled, default: false, null: false
      t.jsonb    :pco_kids_service_types, default: [], null: false
      t.jsonb    :pco_event_tags, default: [], null: false
      t.string   :pco_assessment_field_id
      t.string   :pco_assessment_field_name
      t.timestamps
    end

    add_index :spirely_sync_settings, :church_id, unique: true
    add_foreign_key :spirely_sync_settings, :churches
  end
end
