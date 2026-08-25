class CreateMemberships < ActiveRecord::Migration[7.2]
  def change
    create_table :memberships do |t|
      t.bigint :account_id, null: false
      t.bigint :church_id, null: false
      t.string :role, default: "family", null: false
      t.timestamps
    end

    add_index :memberships, %i[account_id church_id], unique: true
    add_index :memberships, :church_id
    add_foreign_key :memberships, :accounts
    add_foreign_key :memberships, :churches
  end
end
