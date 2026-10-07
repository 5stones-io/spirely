module Spirely
  # A person's membership in a group (PCO role "leader" or "member").
  # left_at is set when the membership disappears from PCO, so history
  # survives for the shrinking-group and drop-off checks.
  class GroupMembership < ApplicationRecord
    ROLES = %w[leader member].freeze

    belongs_to :church
    belongs_to :group, class_name: "Spirely::Group"
    belongs_to :person, class_name: "Spirely::Person"

    validates :pco_membership_id, presence: true, uniqueness: { scope: :church_id }
    validates :role, inclusion: { in: ROLES }

    scope :current, -> { where(left_at: nil) }
    scope :leaders, -> { where(role: "leader") }
  end
end
