module Spirely
  # One PCO Services plan (a service on a date), with its times and who
  # was scheduled. Kudos pays time served per person per plan (5ST-62).
  class ServicePlan < ApplicationRecord
    # What someone served on a plan: the times that count, how many
    # minutes those add up to, and whether their team had no times at all
    # (which earns the flat per-serving rate instead).
    Serving = Struct.new(:plan_people, :times, :minutes, :flat, keyword_init: true) do
      def hours = (minutes / 60.0).round(2)
    end

    belongs_to :church
    belongs_to :service_type, class_name: "Spirely::ServiceType"
    has_many :times, class_name: "Spirely::ServicePlanTime", foreign_key: :plan_id, dependent: :delete_all
    has_many :plan_people, class_name: "Spirely::ServicePlanPerson", foreign_key: :plan_id, dependent: :delete_all

    validates :pco_plan_id, presence: true, uniqueness: { scope: :church_id }

    scope :current, -> { where(removed_at: nil) }
    # Every time in the plan has finished.
    scope :finished, -> { where("spirely_service_plans.ends_at < ?", Time.current) }

    def name = [service_type&.name, title.presence].compact.join(" · ")

    # What one person served, from their Confirmed positions on this plan
    # (`rows`). A time counts when their team was scheduled for it and
    # they didn't decline it; rehearsals and other times only count when
    # the church says so. Overlapping times — someone on two teams, or
    # two times that overlap — are counted once.
    def serving_for(rows, count_rehearsals:)
      rows = rows.select(&:confirmed?)
      return nil if rows.empty?

      scheduled = times.to_a.select { |t| rows.any? { |r| r.scheduled_for?(t) } }
      counted   = scheduled.select { |t| count_rehearsals || t.service? }
      Serving.new(plan_people: rows, times: counted.sort_by(&:starts_at), minutes: union_minutes(counted),
                  flat: scheduled.empty?)
    end

    private

    def union_minutes(times)
      spans = times.map { |t| [t.starts_at, t.ends_at] }.select { |s, e| e > s }.sort_by(&:first)
      merged = spans.each_with_object([]) do |(s, e), out|
        if out.any? && s <= out.last[1]
          out.last[1] = [out.last[1], e].max
        else
          out << [s, e]
        end
      end
      (merged.sum { |s, e| e - s } / 60).round
    end
  end
end
