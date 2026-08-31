class CreateSpirelyFamilyPosts < ActiveRecord::Migration[7.2]
  def change
    # v1 scope (5ST-9): the family-authored news feed — prayer requests,
    # praise reports, accomplishments, milestones. Distinct from
    # Spirely::Announcement (staff -> family, one direction, not yet
    # ported to the gem) and Spirely::ContactNote (staff-authored,
    # never shown to the family it's about) — this is the first
    # family-authored, family-visible content in the gem.
    create_table :spirely_family_posts do |t|
      t.bigint   :church_id, null: false
      t.bigint   :family_id, null: false
      # Which specific guardian in the family actually posted — nil when
      # the signed-in account is the family's own primary contact rather
      # than a separately-invited Guardian (see BaseController#authenticate!
      # / current_guardian). Kept distinct from family_id the same reason
      # Task keeps assignee vs church separate: family_id is "whose post is
      # this," guardian_id is "which person in that family wrote it."
      t.bigint   :guardian_id
      # Optional attribution to a specific kid ("Ellie's first Bible
      # verse") — not required, since a prayer request/praise report is
      # often about the family generally, not one child.
      t.bigint   :child_id
      t.string   :post_type, null: false, default: "prayer_request"
      # Per-post visibility: "church" (any family can see it once
      # approved) vs "staff_only" (only staff, never other families) —
      # author's own choice per post, not a church-wide setting.
      t.string   :audience, null: false, default: "church"
      # No DB-level default, deliberately — Spirely::FamilyPost#default_status
      # decides "approved" vs "pending" per church (family_posts_moderation_enabled)
      # in a before_validation callback, and a column default would populate
      # the in-memory attribute before that callback ever runs (an AR
      # object's schema-default-backed attribute is never nil, so the
      # callback's `self.status ||= ...` guard would silently no-op).
      t.string   :status, null: false
      t.text     :body, null: false
      t.text     :rejected_reason
      t.bigint   :moderated_by_membership_id
      t.datetime :moderated_at
      t.timestamps
    end

    add_index :spirely_family_posts, :church_id
    add_index :spirely_family_posts, :family_id
    add_index :spirely_family_posts, [:church_id, :status]
    add_index :spirely_family_posts, [:church_id, :audience, :status]

    add_foreign_key :spirely_family_posts, :churches
    add_foreign_key :spirely_family_posts, :spirely_families, column: :family_id
    add_foreign_key :spirely_family_posts, :spirely_guardians, column: :guardian_id, on_delete: :nullify
    add_foreign_key :spirely_family_posts, :spirely_children, column: :child_id, on_delete: :nullify
    add_foreign_key :spirely_family_posts, :memberships, column: :moderated_by_membership_id, on_delete: :nullify
  end
end
