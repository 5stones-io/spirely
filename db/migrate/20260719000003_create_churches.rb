class CreateChurches < ActiveRecord::Migration[7.2]
  def change
    create_table :churches do |t|
      t.string   :slug, null: false
      t.string   :name, null: false
      t.string   :enabled_modules, array: true, default: [], null: false
      t.string   :status, default: "pending", null: false
      t.boolean  :session_recording_enabled, default: false, null: false
      t.boolean  :role_preview_enabled, default: false, null: false
      t.string   :public_site_theme, default: "default", null: false
      t.timestamps
    end

    add_index :churches, :slug, unique: true
  end
end
