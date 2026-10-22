# Kudos module, phase 5 (5ST-64): recognition. Shout-outs are thanks from
# one person to another, public (on the church's recognition feed) or
# private. Leaders get a monthly points allowance to give with them.
class CreateSpirelyShoutOuts < ActiveRecord::Migration[7.2]
  def change
    create_table :spirely_shout_outs do |t|
      t.references :church, null: false, foreign_key: true
      t.references :from_account, foreign_key: { to_table: :accounts, on_delete: :nullify }
      t.references :from_person, foreign_key: { to_table: :spirely_people, on_delete: :nullify }
      t.string :from_name, null: false              # as it read when sent
      t.references :to_person, null: false, foreign_key: { to_table: :spirely_people }
      t.text :message, null: false
      t.string :visibility, null: false, default: "public" # public or private
      t.integer :points, null: false, default: 0
      t.string :points_from                          # allowance or staff; nil when no points
      t.references :points_entry, foreign_key: { to_table: :spirely_points_entries, on_delete: :nullify }
      t.datetime :hidden_at
      t.string :hidden_by_name
      t.timestamps
      t.index [:church_id, :created_at]
      t.index [:from_account_id, :created_at]
    end

    # PCO Services team leaders, read by the Services sync, so their
    # allowance can cover Services teams as well as Groups (5ST-64).
    create_table :spirely_service_team_leaders do |t|
      t.references :church, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: { to_table: :spirely_people, on_delete: :cascade }
      t.string :pco_team_id, null: false
      t.string :team_name
      t.timestamps
      t.index [:church_id, :pco_team_id, :person_id], unique: true, name: "index_spirely_service_team_leaders_unique"
    end

    add_column :spirely_people, :kudos_leaderboard_opt_out, :boolean, default: false, null: false
    # Off until staff turn them on: leaderboards rank kids too.
    add_column :spirely_kudos_settings, :leaderboards_enabled, :boolean, default: false, null: false
  end
end
