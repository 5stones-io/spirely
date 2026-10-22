# Kudos module, phase 4 (5ST-63): the store. Staff list items people can
# spend points on; people order online for pickup, or staff check them out
# at a table. Digital items deliver instructions or a code from a pool.
class CreateSpirelyStore < ActiveRecord::Migration[7.2]
  def change
    create_table :spirely_store_items do |t|
      t.references :church, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.integer :points, null: false               # cost of one
      t.string :kind, null: false, default: "physical" # physical or digital
      t.integer :stock                             # physical only; nil means not tracked
      t.text :instructions                         # shown once redeemed (digital kinds)
      t.integer :per_person_limit                  # nil means no limit
      t.string :audience, null: false, default: "everyone" # everyone, adults or kids
      t.datetime :hidden_at
      t.integer :position, null: false, default: 0
      t.timestamps
      t.index [:church_id, :position]
    end

    create_table :spirely_store_orders do |t|
      t.references :church, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: { to_table: :spirely_people }
      t.references :item, null: false, foreign_key: { to_table: :spirely_store_items }
      t.integer :quantity, null: false, default: 1
      t.integer :points, null: false               # total charged
      t.string :status, null: false                # pending, fulfilled or cancelled
      t.string :channel, null: false               # online or checkout
      t.references :placed_by_account, foreign_key: { to_table: :accounts, on_delete: :nullify }
      t.string :placed_by_name
      t.datetime :fulfilled_at
      t.string :fulfilled_by_name
      t.datetime :cancelled_at
      t.string :cancelled_by_name
      t.references :refund_entry, foreign_key: { to_table: :spirely_points_entries, on_delete: :nullify }
      t.timestamps
      t.index [:church_id, :status, :created_at]
    end

    # Digital codes, handed out one per item redeemed.
    create_table :spirely_store_codes do |t|
      t.references :church, null: false, foreign_key: true
      t.references :item, null: false, foreign_key: { to_table: :spirely_store_items, on_delete: :cascade }
      t.string :code, null: false
      t.references :order, foreign_key: { to_table: :spirely_store_orders }
      t.timestamps
      t.index [:item_id, :code], unique: true
      t.index [:item_id, :order_id]
    end
  end
end
