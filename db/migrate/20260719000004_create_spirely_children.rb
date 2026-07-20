class CreateSpirelyChildren < ActiveRecord::Migration[7.2]
  def change
    create_table :spirely_children do |t|
      t.bigint   :family_id, null: false
      t.string   :first_name, null: false
      t.string   :last_name, null: false
      t.date     :birthdate
      t.text     :notes
      t.integer  :grade
      t.string   :pco_person_id
      t.datetime :pco_last_synced_at
      t.uuid     :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.timestamps
    end

    add_index :spirely_children, :family_id
    add_index :spirely_children, :pco_person_id
    add_index :spirely_children, :public_id, unique: true
    add_foreign_key :spirely_children, :spirely_families, column: :family_id
  end
end
