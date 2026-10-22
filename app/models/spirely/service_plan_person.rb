module Spirely
  # One position someone was scheduled for on a Services plan, and whether
  # they confirmed it. Someone on two teams has two rows.
  class ServicePlanPerson < ApplicationRecord
    STATUSES = { "C" => "confirmed", "U" => "unconfirmed", "D" => "declined" }.freeze

    belongs_to :church
    belongs_to :plan, class_name: "Spirely::ServicePlan"
    belongs_to :person, class_name: "Spirely::Person"

    validates :pco_plan_person_id, presence: true, uniqueness: { scope: :plan_id }
    validates :status, inclusion: { in: STATUSES.keys }

    # PCO sends either the letter or the word.
    def self.normalize_status(value)
      v = value.to_s.strip
      STATUSES.key?(v.upcase) ? v.upcase : STATUSES.key(v.downcase)
    end

    def confirmed? = status == "C"

    def scheduled_for?(time)
      (time.team_ids.nil? || time.team_ids.include?(pco_team_id)) && !declined_time_ids.include?(time.pco_plan_time_id)
    end

    # "Band — Guitar", or just the team.
    def role = [team_name, position_name].compact_blank.uniq.join(" — ")
  end
end
