class CreateSpirelyAttendances < ActiveRecord::Migration[7.2]
  def change
    create_table :spirely_attendances do |t|
      t.bigint   :church_id, null: false
      t.bigint   :person_id, null: false
      t.string   :pco_check_in_id, null: false
      t.string   :pco_event_id, null: false
      t.string   :event_name, null: false
      t.string   :pco_location_id
      t.string   :location_name
      t.datetime :checked_in_at, null: false
      t.datetime :checked_out_at
      t.string   :kind, null: false
      t.boolean  :one_time_guest, default: false, null: false
      t.text     :medical_notes
      t.timestamps
    end

    add_index :spirely_attendances, %i[church_id pco_check_in_id], unique: true, name: "index_spirely_attendances_on_church_id_and_pco_check_in_id"
    add_index :spirely_attendances, %i[person_id pco_event_id checked_in_at], name: "index_attendances_on_person_event_checkin"
    add_foreign_key :spirely_attendances, :churches
    add_foreign_key :spirely_attendances, :spirely_people, column: :person_id
  end
end
