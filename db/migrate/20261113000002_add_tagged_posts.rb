# Staff posts that tag children (5ST-78).
#
# - A staff post has no posting family; author_membership is who wrote it.
# - family_post_children is who it tags; its families see it.
# - children.no_photos: the family asked that no photos of this child be
#   posted, so a post with photos can't tag them.
class AddTaggedPosts < ActiveRecord::Migration[7.2]
  def change
    change_column_null :spirely_family_posts, :family_id, true
    add_reference :spirely_family_posts, :author_membership, foreign_key: { to_table: :memberships, on_delete: :nullify }

    create_table :spirely_family_post_children do |t|
      t.references :church, null: false, foreign_key: true
      t.references :family_post, null: false, foreign_key: { to_table: :spirely_family_posts, on_delete: :cascade }
      t.references :child, null: false, foreign_key: { to_table: :spirely_children, on_delete: :cascade }
      t.timestamps
      t.index [:family_post_id, :child_id], unique: true
    end

    add_column :spirely_children, :no_photos, :boolean, default: false, null: false
  end
end
