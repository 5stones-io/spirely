module Spirely
  class Child < ApplicationRecord
    # -1 is PCO's own standard convention for Pre-K, confirmed directly
    # against real production data — not junk. Without it, every Pre-K
    # kid's Child record silently failed the grade validation and never
    # synced at all (found while investigating why two real kids in a
    # specific household weren't showing up anywhere — 16 children
    # church-wide were affected, not just that one household).
    GRADE_DISPLAY = {
      -1 => "Pre-K", 0 => "K",    1 => "1st",  2 => "2nd",  3 => "3rd",
      4 => "4th",  5 => "5th",  6 => "6th",  7 => "7th",
      8 => "8th",  9 => "9th",  10 => "10th", 11 => "11th", 12 => "12th"
    }.freeze

    GRADE_PARSE = {
      "pre-k" => -1, "prek" => -1, "pk" => -1, "preschool" => -1,
      "k" => 0, "kindergarten" => 0,
      "1" => 1, "1st" => 1,  "2" => 2,  "2nd" => 2,  "3" => 3,  "3rd" => 3,
      "4" => 4, "4th" => 4,  "5" => 5,  "5th" => 5,  "6" => 6,  "6th" => 6,
      "7" => 7, "7th" => 7,  "8" => 8,  "8th" => 8,  "9" => 9,  "9th" => 9,
      "10" => 10, "10th" => 10, "11" => 11, "11th" => 11, "12" => 12, "12th" => 12
    }.freeze

    # Canonical tappable allergen vocabulary for the Allergy/Medical
    # Self-Update feature (parent-facing) — kept in sync with the same
    # list hardcoded client-side in medicalApi.ts (this is a small, stable
    # enum, not something worth a round-trip API call to fetch, same
    # convention as VolunteerProfile's pipeline stages).
    ALLERGEN_LABELS = {
      "peanuts"        => "Peanuts",
      "tree_nuts"      => "Tree Nuts",
      "dairy"          => "Dairy/Milk",
      "eggs"           => "Eggs",
      "soy"            => "Soy",
      "wheat"          => "Wheat/Gluten",
      "shellfish"      => "Shellfish",
      "fish"           => "Fish",
      "sesame"         => "Sesame",
      "insect_stings"  => "Insect Stings",
      "latex"          => "Latex",
    }.freeze

    belongs_to :church
    belongs_to :family
    has_many :incidents, class_name: "Spirely::Incident", dependent: :destroy
    has_many :registration_statuses, class_name: "Spirely::RegistrationStatus", dependent: :destroy

    before_validation :inherit_church_from_family

    validates :first_name, :last_name, presence: true
    validates :grade, numericality: { in: -1..12, only_integer: true }, allow_nil: true
    validate :allergens_are_known

    # Accept PCO integer or human string ("3rd", "K") — store as integer
    def grade=(val)
      if val.is_a?(Integer) || val.nil?
        super(val)
      else
        super(GRADE_PARSE[val.to_s.strip.downcase])
      end
    end

    def grade_display
      GRADE_DISPLAY[grade]
    end

    def full_name
      "#{first_name} #{last_name}"
    end

    def age
      return nil if birthdate.nil?
      today = Date.current
      years = today.year - birthdate.year
      years -= 1 if today < birthdate + years.years
      years
    end

    # The "Linked Dual-Role Records" gap, resolved without a schema
    # change: Child and Spirely::Person are both synced from PCO
    # independently (PcoInboundPeopleSyncJob populates Child#pco_person_id;
    # PcoAttendanceSyncJob lazily creates a Person for anyone — kid or
    # adult — who checks in), but PCO's own person id is the same value on
    # both sides, so it's a reliable join key rather than a new FK. Nil
    # until both syncs have actually run for this specific kid — a kid who
    # exists in Spirely (synced via a household) but has never personally
    # checked in via PCO Check-Ins won't have a Person yet.
    def person
      return nil if pco_person_id.blank?
      church.people.find_by(pco_person_id: pco_person_id)
    end

    # The one blessed way to change allergy/medical data — stamps
    # allergy_updated_at in the same save, so "when did a parent last
    # touch this" (surfaced to staff) can never drift out of sync with
    # the fields it's describing the way two separate writes could.
    def update_medical!(allergens:, allergy_notes:)
      update!(allergens: allergens, allergy_notes: allergy_notes, allergy_updated_at: Time.current)
    end

    # Combines the structured allergen picks + free-text detail into one
    # display string (e.g. "Peanuts, Tree Nuts — carries an EpiPen") for
    # anywhere that just wants a single flag/summary line rather than the
    # raw fields — CheckedInNowCalculator's roster alert, primarily.
    def allergy_summary
      parts = []
      parts << allergens.map { |a| ALLERGEN_LABELS[a] || a.to_s.humanize }.join(", ") if allergens.present?
      parts << allergy_notes if allergy_notes.present?
      parts.join(" — ").presence
    end

    private

    def allergens_are_known
      unknown = Array(allergens) - ALLERGEN_LABELS.keys
      errors.add(:allergens, "contains unknown value(s): #{unknown.join(', ')}") if unknown.any?
    end

    def inherit_church_from_family
      self.church_id ||= family&.church_id
    end
  end
end
