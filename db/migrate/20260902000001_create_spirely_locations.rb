class CreateSpirelyLocations < ActiveRecord::Migration[7.2]
  def change
    create_table :spirely_locations do |t|
      t.bigint :church_id, null: false
      t.string :pco_location_id, null: false
      t.string :name, null: false
      t.timestamps
    end

    add_index :spirely_locations, %i[church_id pco_location_id], unique: true, name: "index_spirely_locations_on_church_id_and_pco_location_id"
    add_foreign_key :spirely_locations, :churches
  end
end
