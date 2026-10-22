module Spirely
  # One line in a person's Kudos points ledger (5ST-60). Points are signed:
  # positive for earned, negative for spent or deducted. Entries are never
  # edited — a mistake is fixed with a deduction, so history stays honest.
  class PointsEntry < ApplicationRecord
    SOURCES = %w[manual checkin group_attendance service promo_code shout_out redemption refund adjustment].freeze

    belongs_to :church
    belongs_to :person, class_name: "Spirely::Person"
    belongs_to :awarded_by_account, class_name: "Account", optional: true

    validates :points, numericality: { only_integer: true, other_than: 0 }
    validates :source, inclusion: { in: SOURCES }
    validates :occurred_on, presence: true
    validates :person_id, uniqueness: { scope: [:source_type, :source_id] }, if: :source_id?
    validate :person_in_church

    scope :newest_first, -> { order(occurred_on: :desc, id: :desc) }
    scope :credits, -> { where("points > 0") }
    scope :debits,  -> { where("points < 0") }

    private

    def person_in_church
      errors.add(:person, "must belong to this church") if person && person.church_id != church_id
    end
  end
end
