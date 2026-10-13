# Module-scoped custom domains (5ST-12): a church's domain can show only
# some of its modules, with its own name and logo — e.g. kidz.jccag.org
# for Kids Ministry and portal.jccag.org for Small Groups. `modules` nil
# means the domain shows every module the church has on, as before.
class AddModuleScopeToCustomDomains < ActiveRecord::Migration[7.2]
  def change
    add_column :custom_domains, :modules, :string, array: true
    add_column :custom_domains, :display_name, :string
    add_column :custom_domains, :logo_shape, :string
  end
end
