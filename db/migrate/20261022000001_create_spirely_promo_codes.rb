# Kudos module, phase 2 (5ST-61): promo codes. Staff create a code worth
# some points; people claim it from My Points, once each. A claim is a
# points entry pointing back at the code, so the ledger's one-per-source
# index is what enforces "once per person".
class CreateSpirelyPromoCodes < ActiveRecord::Migration[7.2]
  def change
    create_table :spirely_promo_codes do |t|
      t.references :church, null: false, foreign_key: true
      t.string :code, null: false               # stored upper-case, so claims are case-insensitive
      t.string :label, null: false
      t.integer :points, null: false
      t.integer :max_uses                       # nil means no limit
      t.date :expires_on                        # last day it can be claimed; nil means never
      t.datetime :turned_off_at
      t.references :created_by_account, foreign_key: { to_table: :accounts, on_delete: :nullify }
      t.string :created_by_name
      t.timestamps
      t.index [:church_id, :code], unique: true
    end
  end
end
