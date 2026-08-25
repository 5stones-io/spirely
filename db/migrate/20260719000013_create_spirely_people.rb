class CreateSpirelyPeople < ActiveRecord::Migration[7.2]
  def change
    create_table :spirely_people do |t|
      t.bigint   :church_id, null: false
      t.string   :pco_person_id, null: false
      t.string   :first_name, null: false
      t.string   :last_name
      t.string   :email
      t.string   :phone
      t.boolean  :child, default: false, null: false
      t.date     :birthdate
      t.datetime :pco_last_synced_at
      t.string   :assessment_result
      t.datetime :assessment_synced_at
      t.timestamps
    end

    add_index :spirely_people, %i[church_id pco_person_id], unique: true
    add_foreign_key :spirely_people, :churches
  end
end
