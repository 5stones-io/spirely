# Time card: hours that staff log for work outside normal volunteer hours.
# Every entry counts toward a category code (the church's stand-in for a
# billing code). An entry can point at a task, which carries its own
# category; otherwise the person picks a category directly.
class CreateSpirelyTimeEntries < ActiveRecord::Migration[7.2]
  def change
    create_table :spirely_time_categories do |t|
      t.references :church, null: false, foreign_key: true
      t.string :code, null: false                  # stored upper-case, e.g. FAC
      t.string :name, null: false                  # e.g. Facilities
      t.datetime :archived_at                      # turned off, not deleted — past hours keep their code
      t.timestamps
      t.index [:church_id, :code], unique: true
    end

    # Required for new tasks (enforced where tasks are created); existing
    # tasks have none until someone edits them.
    add_reference :spirely_tasks, :time_category, foreign_key: { to_table: :spirely_time_categories }

    # Staff who log time without being admins. Admins and owners always can.
    add_column :memberships, :staff, :boolean, default: false, null: false

    create_table :spirely_time_entries do |t|
      t.references :church, null: false, foreign_key: true
      t.references :membership, null: false, foreign_key: true
      t.references :task, foreign_key: { to_table: :spirely_tasks, on_delete: :nullify }
      t.references :time_category, null: false, foreign_key: { to_table: :spirely_time_categories }
      t.string :title, null: false
      t.text :description
      t.decimal :hours, precision: 5, scale: 2, null: false
      t.date :worked_on, null: false
      t.timestamps
      t.index [:church_id, :worked_on]
      t.index [:membership_id, :worked_on]
    end
  end
end
