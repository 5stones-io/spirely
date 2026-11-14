# The security code Planning Center prints on a child's tag and the
# parent's pickup tag, so staff can match a child to a parent from Checked
# in now when a tag is lost.
class AddSecurityCodeToAttendances < ActiveRecord::Migration[7.2]
  def change
    add_column :spirely_attendances, :security_code, :string
  end
end
