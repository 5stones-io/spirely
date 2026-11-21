# Create Account on the church's site (5ST-85): a parent asks for an
# account, confirms their email from the link we send, and then either sets
# up their account (we have them on file) or fills in a new-family form
# that staff approve.
#
# - phone (10 digits) and email are what the parent typed on Create Account;
#   email_confirmed_at is when they opened the link.
# - invitation_id / family_id: the invite we made for a family on file, or
#   the family approving the form created.
# - details holds the form: parent name, address and kids (FamilySignup
#   documents the shape). Nothing is added to the church's families until
#   staff approve it.
# - matched_family_id: a family on file with the same phone, so staff can
#   spot a duplicate.
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
      t.datetime :email_confirmed_at
      t.datetime :submitted_at
      t.references :matched_family, foreign_key: { to_table: :spirely_families, on_delete: :nullify }
      t.references :family, foreign_key: { to_table: :spirely_families, on_delete: :nullify }
      t.references :invitation, foreign_key: { to_table: :spirely_invitations, on_delete: :nullify }
      t.references :reviewed_by_account, foreign_key: { to_table: :accounts, on_delete: :nullify }
      t.datetime :reviewed_at
      t.timestamps
    end
    add_index :spirely_family_signups, :token, unique: true
    add_index :spirely_family_signups, [:church_id, :status]
  end
end
