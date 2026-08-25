class CreateSpirelyStaffInvitations < ActiveRecord::Migration[7.2]
  def change
    create_table :spirely_staff_invitations do |t|
      t.bigint   :church_id, null: false
      t.string   :token, null: false
      t.string   :invited_first_name
      t.string   :invited_email
      t.string   :invited_phone
      t.datetime :expires_at, null: false
      t.datetime :accepted_at
      t.timestamps
    end

    add_index :spirely_staff_invitations, :church_id
    add_index :spirely_staff_invitations, :token, unique: true
    add_foreign_key :spirely_staff_invitations, :churches
  end
end
