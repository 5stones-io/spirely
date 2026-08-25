module Spirely
  class Attendance < ApplicationRecord
    KINDS = %w[regular guest volunteer].freeze

    belongs_to :church
    belongs_to :person, class_name: "Spirely::Person"

    before_validation :inherit_church_from_person

    validates :pco_check_in_id, presence: true, uniqueness: { scope: :church_id }
    validates :pco_event_id, :event_name, :checked_in_at, presence: true
    validates :kind, inclusion: { in: KINDS }

    # Visitors excluded from baseline calculation entirely - confirmed
    # against PCO's real CheckIn schema (kind: guest, or one_time_guest
    # true for a check-in with no corresponding person record at all).
    # See spec Section 3.1.
    scope :countable_for_baseline, -> { where(one_time_guest: false).where.not(kind: "guest") }

    private

    def inherit_church_from_person
      self.church_id ||= person&.church_id
    end
  end
end
