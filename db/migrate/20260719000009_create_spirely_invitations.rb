class CreateSpirelyInvitations < ActiveRecord::Migration[7.2]
  def change
    create_table :spirely_invitations do |t|
      t.bigint   :church_id, null: false
      t.bigint   :family_id, null: false
      t.bigint   :guardian_id
      t.string   :token, null: false
      t.datetime :expires_at, null: false
      t.datetime :accepted_at
      t.timestamps
    end

    add_index :spirely_invitations, :church_id
    add_index :spirely_invitations, :family_id
    add_index :spirely_invitations, :guardian_id
    add_index :spirely_invitations, :token, unique: true
    add_foreign_key :spirely_invitations, :churches
    add_foreign_key :spirely_invitations, :spirely_families, column: :family_id
    add_foreign_key :spirely_invitations, :spirely_guardians, column: :guardian_id
  end
end
