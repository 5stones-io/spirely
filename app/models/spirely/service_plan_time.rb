module Spirely
  # A time in a Services plan: a service, a rehearsal, or something else.
  # team_ids is which teams PCO scheduled for it; nil means PCO didn't
  # say, and every team is treated as scheduled.
  class ServicePlanTime < ApplicationRecord
    TYPES = %w[service rehearsal other].freeze

    belongs_to :church
    belongs_to :plan, class_name: "Spirely::ServicePlan"

    validates :pco_plan_time_id, presence: true, uniqueness: { scope: :plan_id }
    validates :time_type, inclusion: { in: TYPES }
    validates :starts_at, :ends_at, presence: true

    def service? = time_type == "service"
  end
end
