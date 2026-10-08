module Spirely
  # A PCO Groups group, synced read-only by PcoGroupsSyncJob. Core data
  # shared by any module that uses groups (Small Groups today, Kids
  # Ministry's children's groups later).
  class Group < ApplicationRecord
    belongs_to :church
    belongs_to :group_type, class_name: "Spirely::GroupType", optional: true
    has_many :memberships, class_name: "Spirely::GroupMembership", dependent: :destroy
    has_many :events, class_name: "Spirely::GroupEvent", dependent: :destroy
    has_many :applications, class_name: "Spirely::GroupApplication", dependent: :destroy

    validates :pco_group_id, presence: true, uniqueness: { scope: :church_id }
    validates :name, presence: true

    # Still in PCO and not archived there.
    scope :active, -> { where(removed_at: nil, archived_at: nil) }

    def audience
      group_type&.audience || "adults"
    end

    def children?
      audience == "children"
    end
  end
end
