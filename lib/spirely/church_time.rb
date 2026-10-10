module Spirely
  # A church's local time zone. Hosts that store Church#timezone (an IANA
  # name, possibly followed by a " — description" label) use it; anything
  # else falls back to the app's own Time.zone.
  module ChurchTime
    def self.zone(church)
      name = church.has_attribute?(:timezone) ? church.timezone.to_s.split(" — ").first.to_s.strip : ""
      ActiveSupport::TimeZone[name] || Time.zone
    end

    def self.today(church) = zone(church).today
  end
end
