module Spirely
  # A church's Kudos settings (5ST-60), one row per church, created the
  # first time anything reads them.
  #
  # `rates` holds the automatic earning rates (5ST-61):
  #   "checkin"          points per check-in (0 = check-ins don't earn)
  #   "group_attendance" points per group meeting attended
  #   "checkin_events"   { pco_event_id => points } for Check-Ins events
  #                      that earn a different amount (e.g. Wednesday
  #                      Rangers vs Sunday). 0 there means that event
  #                      doesn't earn at all.
  #   "service_hour"     points per hour served on a Services plan (5ST-62)
  #   "service_flat"     points per serving for teams with no plan times
  # All default to 0, so turning Kudos on never starts paying out until
  # an admin picks a rate. count_rehearsals adds rehearsal and other plan
  # times to hours served; off, only service times count.
  class KudosSetting < ApplicationRecord
    MAX_RATE = 10_000

    belongs_to :church

    validates :earning_starts_on, presence: true
    validate :rates_are_points

    # Defaults the earning start date to today, so turning the module on
    # doesn't pay out years of history unless the church moves it back.
    def self.for(church)
      church.kudos_setting || church.create_kudos_setting!(earning_starts_on: Spirely::ChurchTime.today(church))
    rescue ActiveRecord::RecordNotUnique
      church.reload.kudos_setting
    end

    def checkin_points = rates.fetch("checkin", 0).to_i
    def group_points = rates.fetch("group_attendance", 0).to_i
    def checkin_event_points = rates.fetch("checkin_events", {}).transform_values(&:to_i)
    def service_hour_points = rates.fetch("service_hour", 0).to_i
    def service_flat_points = rates.fetch("service_flat", 0).to_i

    def earns_for_serving? = service_hour_points.positive? || service_flat_points.positive?

    # Points one check-in at this event earns.
    def points_for_checkin(pco_event_id)
      checkin_event_points.fetch(pco_event_id.to_s, checkin_points)
    end

    def earns_anything?
      checkin_points.positive? || group_points.positive? || checkin_event_points.values.any?(&:positive?) ||
        earns_for_serving?
    end

    private

    def rates_are_points
      values = [rates["checkin"], rates["group_attendance"], rates["service_hour"], rates["service_flat"],
                *rates.fetch("checkin_events", {}).values].compact
      return if values.all? { |v| v.is_a?(Integer) && v.between?(0, MAX_RATE) }

      errors.add(:base, "Points per check-in, meeting or hour must be a whole number from 0 to #{MAX_RATE.to_fs(:delimited)}.")
    end
  end
end
