# Kudos helpers: members who run the store table (checkout and the pickup
# queue) without being admins. Admins and owners always can.
class AddKudosHelperToMemberships < ActiveRecord::Migration[7.2]
  def change
    add_column :memberships, :kudos_helper, :boolean, default: false, null: false
  end
end
