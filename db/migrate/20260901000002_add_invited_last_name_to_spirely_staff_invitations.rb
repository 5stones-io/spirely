class AddInvitedLastNameToSpirelyStaffInvitations < ActiveRecord::Migration[7.2]
  def change
    add_column :spirely_staff_invitations, :invited_last_name, :string
  end
end
