class CreateSpirelySyncSettings < ActiveRecord::Migration[7.2]
  def change
    create_table :spirely_sync_settings do |t|
      t.boolean  :inbound_people_sync, default: true, null: false
      t.boolean  :outbound_people_sync, default: false, null: false
      t.integer  :sync_frequency_hours, default: 6, null: false
      t.string   :conflict_resolution, default: "pco_wins", null: false
      t.datetime :last_synced_at
      t.string   :pco_ministry_tag
      t.boolean  :auto_sync_enabled, default: false, null: false
      t.timestamps
    end
  end
end
