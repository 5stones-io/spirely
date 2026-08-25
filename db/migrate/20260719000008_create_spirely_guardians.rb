class CreateSpirelyGuardians < ActiveRecord::Migration[7.2]
  def change
    create_table :spirely_guardians do |t|
      t.bigint :church_id, null: false
      t.bigint :family_id, null: false
      t.string :first_name, null: false
      t.string :last_name
      t.string :phone
      t.string :email
      t.string :relationship
      t.string :pco_person_id
      t.bigint :account_id
      t.timestamps
    end

    add_index :spirely_guardians, %i[church_id account_id], unique: true, where: "account_id IS NOT NULL"
    add_index :spirely_guardians, %i[church_id pco_person_id], unique: true, where: "pco_person_id IS NOT NULL"
    add_index :spirely_guardians, :church_id
    add_index :spirely_guardians, :family_id
    add_foreign_key :spirely_guardians, :churches
    add_foreign_key :spirely_guardians, :spirely_families, column: :family_id
  end
end
