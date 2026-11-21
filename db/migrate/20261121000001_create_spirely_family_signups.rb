# Create Account on the church's site (5ST-85): a parent we don't have on
# file gets a link to a new-family form; staff approve what they send.
#
# - phone (10 digits) and email are what the parent typed on Create Account.
# - details holds the form: parent name, address and kids (FamilySignup
#   documents the shape). Nothing is added to the church's families until
#   staff approve it; family_id is the family that approval created.
# - matched_family_id: a family on file with the same phone or email that we
#   couldn't send an invite to, so staff can spot a duplicate.
class CreateSpirelyFamilySignups < ActiveRecord::Migration[7.2]
  def change
    create_table :spirely_family_signups do |t|
      t.references :church, null: false, foreign_key: true
      t.string :phone, null: false
      t.string :email, null: false
      t.string :token, null: false
      t.datetime :expires_at, null: false
      t.string :status, null: false, default: "started"
      t.jsonb :details, null: false, default: {}
      t.datetime :submitted_at
      t.references :matched_family, foreign_key: { to_table: :spirely_families, on_delete: :nullify }
      t.references :family, foreign_key: { to_table: :spirely_families, on_delete: :nullify }
      t.references :reviewed_by_account, foreign_key: { to_table: :accounts, on_delete: :nullify }
      t.datetime :reviewed_at
      t.timestamps
    end
    add_index :spirely_family_signups, :token, unique: true
    add_index :spirely_family_signups, [:church_id, :status]
  end
end
