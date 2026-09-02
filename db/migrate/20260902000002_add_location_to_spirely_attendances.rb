class AddLocationToSpirelyAttendances < ActiveRecord::Migration[7.2]
  def change
    add_column :spirely_attendances, :location_id, :bigint
    add_index :spirely_attendances, :location_id
    add_foreign_key :spirely_attendances, :spirely_locations, column: :location_id
  end
end
