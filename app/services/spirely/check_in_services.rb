module Spirely
  # A church's Check-Ins services over the last WINDOW (5ST-75): one per
  # service time (Planning Center EventTime slot: event + day + time), with
  # every date it happened and who came each time. Used for the Child
  # sheet's attendance rows (AttendanceHistory) and for Attendance Nudges,
  # which flag a kid against their own usual service.
  #
  # - An occurrence is one EventTime someone checked in for, so a service
  #   nobody came to that week has no date.
  # - A time that starts inside a later time's check-in window counts toward
  #   that later service (see #joined_times).
  # - A service that only happened once (a musical) is left out.
  # - Limited to the church's mapped kids services when any are mapped.
  # - countable_only: leaves guest and one-time-guest check-ins out of both
  #   the dates and the attendance, as Attendance Nudges always have.
  class CheckInServices
    WINDOW      = 26.weeks
    JOIN_WITHIN = 90 # minutes; see #joined_times

    SLOT = %i[event_name event_time_day_of_week event_time_hour event_time_minute].freeze

    # key: stable id for the service ("JCC Kidz|0|11|0").
    # dates: ISO dates it happened, oldest first, in the church's time zone.
    Service = Struct.new(:key, :event_name, :title, :sort_key, :dates, :attendance, keyword_init: true) do
      def attended_dates(person_id) = attendance.fetch(person_id, Set.new)
    end

    ServiceTime = Struct.new(:id, :slot, :starts_at, :shows_at, :name)

    def initialize(church, countable_only: false)
      @church = church
      @countable_only = countable_only
    end

    def all
      @all ||= build
    end

    def for_person(person_id)
      all.select { |s| s.attendance.key?(person_id) }
    end

    private

    def zone = @zone ||= Spirely::ChurchTime.zone(@church)

    def day_date(time) = time.in_time_zone(zone).to_date.iso8601

    def scope
      s = @church.attendances.where.not(pco_event_time_id: nil).where(event_time_starts_at: WINDOW.ago..)
      s = s.countable_for_baseline if @countable_only
      names = kids_event_names
      names.any? ? s.where(event_name: names) : s
    end

    def build
      times = scope.group(:pco_event_time_id, *SLOT)
                   .pluck(:pco_event_time_id, *SLOT, Arel.sql("MIN(event_time_starts_at)"),
                          Arel.sql("MIN(event_time_shows_at)"), Arel.sql("MAX(event_time_name)"))
                   .map { |id, e, w, h, m, starts, shows, name| ServiceTime.new(id, [e, w, h, m], starts, shows, name) }
      return [] if times.empty?

      into = joined_times(times)
      people = Hash.new { |h, k| h[k] = [] }
      scope.distinct.pluck(:pco_event_time_id, :person_id).each { |t, p| people[t] << p }

      times.group_by { |t| into[t.id].slot }.filter_map do |slot, members|
        dates = members.map { |t| day_date(t.starts_at) }.uniq.sort
        next if dates.size < 2 # a one-off, like a musical

        attendance = Hash.new { |h, k| h[k] = Set.new }
        members.each { |t| people[t.id].each { |p| attendance[p] << day_date(t.starts_at) } }
        event_name, wday, hour, minute = slot
        label = members.select { |t| t.slot == slot && t.name }.max_by(&:starts_at)&.name || slot_label(wday, hour, minute)
        Service.new(key: slot.join("|"), event_name: event_name, title: [event_name, label].compact.join(" · "),
                    sort_key: [wday || 7, (hour || 0) * 60 + (minute || 0)], dates: dates,
                    attendance: attendance.to_h)
      end.sort_by { |s| [s.sort_key, s.title] }
    end

    # Each service time's id => the service time whose row it counts toward.
    # A time that starts inside a later time's check-in window (same event,
    # same day) counts toward the latest such time: jccag's 11:00 check-in
    # opens at 8:30, so its 9:00 and 10:10 times (10:10 is during Sunday
    # School, whose attendance is kept in Groups) count toward 11:00, while
    # 4 PM stays apart from 6 PM (opens 5:30). Check-ins synced before the
    # window was stored fall back to starting within JOIN_WITHIN of the
    # next time. (A church setting for this is planned: 5ST-76.)
    def joined_times(times)
      into = {}
      times.group_by { |t| [t.slot.first, day_date(t.starts_at)] }.each_value do |day|
        later = []
        day.sort_by(&:starts_at).reverse_each do |t|
          host = later.reverse.find { |u| u.starts_at > t.starts_at && covers?(u, t) }
          into[t.id] = host ? into[host.id] : t
          later.unshift(t)
        end
      end
      into
    end

    def covers?(later, early)
      return later.shows_at <= early.starts_at if later.shows_at

      later.starts_at - early.starts_at < JOIN_WITHIN.minutes
    end

    def kids_event_names
      Array(@church.sync_setting&.pco_kids_service_types).filter_map { |st| st["check_ins_event_name"] }.uniq
    end

    # 0, 11, 0 → "Sunday 11:00 AM" (PCO's day_of_week is 0 = Sunday).
    def slot_label(wday, hour, minute)
      return nil if wday.nil? || hour.nil?

      "#{Date::DAYNAMES[wday]} #{(hour % 12).zero? ? 12 : hour % 12}:#{format('%02d', minute.to_i)} #{hour < 12 ? 'AM' : 'PM'}"
    end
  end
end
