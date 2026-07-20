class CreateSpirelyFamilies < ActiveRecord::Migration[7.2]
  def change
    create_table :spirely_families do |t|
      t.string   :family_name
      t.string   :email
      t.string   :phone
      t.string   :address
      t.string   :primary_contact_first_name
      t.string   :primary_contact_last_name
      t.string   :pco_person_id
      t.string   :pco_household_id
      t.boolean  :pco_sync_enabled, default: true, null: false
      t.datetime :pco_last_synced_at
      t.bigint   :account_id
      t.timestamps
    end

    add_index :spirely_families, :account_id, unique: true, where: "account_id IS NOT NULL"
    add_index :spirely_families, :email
    add_index :spirely_families, :pco_person_id
    add_index :spirely_families, :pco_household_id
    add_foreign_key :spirely_families, :accounts, on_delete: :nullify
  end
end
