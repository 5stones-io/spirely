# Prayer requests and praise reports page (5ST-79).
#
# - People say they're praying for a request: one row per account and post.
# - A family marks its own request answered, with a note about what
#   happened; the praise report it can share points back at the request.
class AddPrayersToSpirelyFamilyPosts < ActiveRecord::Migration[7.2]
  def change
    create_table :spirely_family_post_prayers do |t|
      t.references :church, null: false, foreign_key: true
      t.references :family_post, null: false, foreign_key: { to_table: :spirely_family_posts, on_delete: :cascade }
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps
      t.index [:family_post_id, :account_id], unique: true
    end

    add_column :spirely_family_posts, :prayers_count, :integer, default: 0, null: false
    add_column :spirely_family_posts, :answered_at, :datetime
    add_column :spirely_family_posts, :answer_note, :text
    add_reference :spirely_family_posts, :answers_post,
                  foreign_key: { to_table: :spirely_family_posts, on_delete: :nullify }
  end
end
