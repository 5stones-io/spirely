class AddFamilyPostsModerationEnabledToChurches < ActiveRecord::Migration[7.2]
  def change
    # Per-church toggle (5ST-9): when true, a new FamilyPost starts
    # "pending" and needs a staff approve/reject before it's visible
    # church-wide — see Spirely::FamilyPost#default_status. Off by
    # default so a church doesn't silently gain a moderation queue it
    # never asked for.
    add_column :churches, :family_posts_moderation_enabled, :boolean, null: false, default: false
  end
end
