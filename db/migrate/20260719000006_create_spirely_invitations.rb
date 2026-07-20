class CreateSpirelyInvitations < ActiveRecord::Migration[7.2]
  def change
    create_table :spirely_invitations do |t|
      t.bigint   :family_id, null: false
      t.string   :token, null: false
      t.datetime :expires_at, null: false
      t.datetime :accepted_at
      t.timestamps
    end

    add_index :spirely_invitations, :family_id
    add_index :spirely_invitations, :token, unique: true
    add_foreign_key :spirely_invitations, :spirely_families, column: :family_id
  end
end
