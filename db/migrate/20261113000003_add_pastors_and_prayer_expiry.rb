# 5ST-79 follow-up: a Pastor flag on memberships (who sees "Pastors only"
# prayer requests), and when a prayer request was last renewed (they
# expire 30 days after being posted or renewed).
class AddPastorsAndPrayerExpiry < ActiveRecord::Migration[7.2]
  def change
    add_column :memberships, :pastor, :boolean, null: false, default: false
    add_column :spirely_family_posts, :renewed_at, :datetime
  end
end
