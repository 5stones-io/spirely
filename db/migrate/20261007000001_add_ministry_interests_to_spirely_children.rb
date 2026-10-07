class AddMinistryInterestsToSpirelyChildren < ActiveRecord::Migration[7.2]
  def change
    add_column :spirely_children, :ministry_interests, :text, array: true, null: false, default: []
    # Dedicated timestamp, same reasoning as allergy_updated_at — a staff
    # edit to first_name/grade/etc shouldn't make interests look
    # "recently changed."
    add_column :spirely_children, :ministry_interests_updated_at, :datetime
    # Both parents and staff can edit interests, so staff need to see
    # whose answer they're looking at ("Updated 3 weeks ago by Sarah
    # Johnson (parent)"). Nullified rather than cascaded if the account
    # goes away — the interests themselves are still valid.
    add_reference :spirely_children, :ministry_interests_updated_by,
                  foreign_key: { to_table: :accounts, on_delete: :nullify }, null: true
    add_column :spirely_children, :ministry_interests_updated_by_role, :string
  end
end
