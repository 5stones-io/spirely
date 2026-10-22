module Spirely
  # Thanks from one person to another (Kudos, 5ST-64) — called shout-outs
  # so they aren't confused with the Kudos module itself. Public ones show
  # on the church's recognition feed; private ones only to the people
  # involved. Leaders can attach points from their monthly allowance, and
  # staff can add points to any shout-out. See Spirely::Recognition for who
  # can see what.
  class ShoutOut < ApplicationRecord
    VISIBILITIES = %w[public private].freeze
    MAX_MESSAGE = 500

    belongs_to :church
    belongs_to :from_account, class_name: "Account", optional: true
    belongs_to :from_person, class_name: "Spirely::Person", optional: true
    belongs_to :to_person, class_name: "Spirely::Person"
    belongs_to :points_entry, class_name: "Spirely::PointsEntry", optional: true

    validates :from_name, presence: true
    validates :message, presence: true, length: { maximum: MAX_MESSAGE }
    validates :visibility, inclusion: { in: VISIBILITIES }
    validates :points, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :points_from, inclusion: { in: %w[allowance staff] }, allow_nil: true

    scope :shown, -> { where(hidden_at: nil) }
    scope :newest_first, -> { order(created_at: :desc, id: :desc) }

    def public? = visibility == "public"
    def hidden? = hidden_at.present?
    def to_kid? = !!to_person.child
  end
end
