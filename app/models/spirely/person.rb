module Spirely
  # The CRM foundation — a normalized, PCO-synced person, covering adults
  # and kids uniformly via `child` (mirrors PCO's own attribute of the same
  # name). Deliberately separate from Family/Guardian/Child, which stay
  # focused on the kids-check-in/family-management use case they already
  # serve — Person exists for CRM entities (starting with VolunteerProfile)
  # that need to reference "some PCO person" regardless of whether that
  # person happens to be a family's guardian.
  class Person < ApplicationRecord
    belongs_to :church
    has_one :volunteer_profile, class_name: "Spirely::VolunteerProfile", dependent: :destroy
    has_many :attendances, class_name: "Spirely::Attendance", dependent: :destroy
    has_many :contact_notes, class_name: "Spirely::ContactNote", dependent: :destroy

    validates :pco_person_id, presence: true, uniqueness: { scope: :church_id }
    validates :first_name, presence: true

    def full_name
      [first_name, last_name].compact.join(" ")
    end

    def assessment_completed?
      assessment_result.present?
    end
  end
end
