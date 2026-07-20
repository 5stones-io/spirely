class CreateSpirelyGuardians < ActiveRecord::Migration[7.2]
  def change
    create_table :spirely_guardians do |t|
      t.bigint :family_id, null: false
      t.string :first_name, null: false
      t.string :last_name
      t.string :phone
      t.string :email
      t.string :relationship
      t.timestamps
    end

    add_index :spirely_guardians, :family_id
    add_foreign_key :spirely_guardians, :spirely_families, column: :family_id
  end
end
