module Spirely
  # A person's recent attendance, one row per service or group they're part
  # of (5ST-75), for the staff Child sheet's attended/missed dots.
  #
  # - Check-ins: one row per service time (Planning Center EventTime slot:
  #   event + day + time) the person has checked in for in the last
  #   WINDOW, limited to the church's mapped kids services when any are
  #   mapped. An occurrence is one EventTime someone checked in for, so a
  #   service nobody came to that week has no dot, and nothing depends on
  #   the church's time zone setting.
  # - Groups: one row per group type the person is currently in (their
  #   class as the subtitle), counting meetings since they joined where
  #   attendance was taken — the same rule as GroupNudgeCalculator.
  #
  # Each row keeps its last MEETINGS_SHOWN, oldest first. Rows are ordered
  # through the week (Sunday first).
  class AttendanceHistory
    MEETINGS_SHOWN = 10
    WINDOW         = 26.weeks
    JOIN_WITHIN    = 60 # minutes; see #joined_slots

    SLOT = %i[event_name event_time_day_of_week event_time_hour event_time_minute].freeze

    Row = Struct.new(:kind, :title, :subtitle, :meetings, :sort_key, keyword_init: true)

    def initialize(church, person)
      @church = church
      @person = person
    end

    def rows
      (check_in_rows + group_rows).sort_by { |r| [r.sort_key, r.title] }
    end

    private

    def zone = @zone ||= Spirely::ChurchTime.zone(@church)

    def day_date(time) = time.in_time_zone(zone).to_date.iso8601

    def check_in_rows
      scope = @church.attendances.where.not(pco_event_time_id: nil).where(event_time_starts_at: WINDOW.ago..)
      names = kids_event_names
      scope = scope.where(event_name: names) if names.any?
      mine  = scope.where(person_id: @person.id)
      my_slots = mine.distinct.pluck(*SLOT)
      return [] if my_slots.empty?

      into = joined_slots(scope.distinct.pluck(*SLOT))
      my_slots.map { |s| into[s] }.uniq.filter_map do |target|
        event_name, wday, hour, minute = target
        slots = into.select { |_, t| t == target }.keys.map { |s| scope.where(SLOT.zip(s).to_h) }.reduce(:or)
        dates = slots.distinct.pluck(:event_time_starts_at).map { |at| day_date(at) }.uniq.sort.last(MEETINGS_SHOWN)
        next if dates.empty?

        attended = slots.where(person_id: @person.id).pluck(:event_time_starts_at).map { |at| day_date(at) }.to_set
        label = scope.where(SLOT.zip(target).to_h).where.not(event_time_name: nil)
                     .order(event_time_starts_at: :desc).pick(:event_time_name) || slot_label(wday, hour, minute)
        Row.new(kind: "check_in", title: [event_name, label].compact.join(" · "), subtitle: nil,
                meetings: dates.map { |d| { date: d, attended: attended.include?(d) } },
                sort_key: [wday || 7, (hour || 0) * 60 + (minute || 0)])
      end
    end

    # Each slot => the slot whose row it counts toward. A service time that
    # starts less than JOIN_WITHIN before the next time of the same event on
    # the same day counts toward that later one: jccag's check-in window
    # opens at 10:10, during Sunday School, for the 11:00 service, and
    # Sunday School's attendance is kept in Groups. (A church setting for
    # this is planned; see Linear.)
    def joined_slots(slots)
      into = {}
      slots.group_by { |e, w, _, _| [e, w] }.each_value do |day|
        timed, untimed = day.partition { |_, w, h, _| w && h }
        untimed.each { |s| into[s] = s }
        later = nil
        timed.sort_by { |s| minutes(s) }.reverse_each do |s|
          into[s] = later && minutes(later) - minutes(s) < JOIN_WITHIN ? into[later] : s
          later = s
        end
      end
      into
    end

    def minutes(slot) = slot[2] * 60 + slot[3].to_i

    def group_rows
      memberships = @church.group_memberships.current.where(person_id: @person.id)
                           .joins(:group).where(spirely_groups: { removed_at: nil, archived_at: nil })
                           .includes(group: :group_type)
      taken = @church.group_attendances.select(:group_event_id)

      memberships.group_by { |m| m.group.group_type || m.group }.filter_map do |key, ms|
        events = ms.flat_map do |m|
          q = m.group.events.held.past.where(id: taken)
          q = q.where(starts_at: m.joined_at..) if m.joined_at
          q.to_a
        end.uniq.sort_by(&:starts_at).last(MEETINGS_SHOWN)
        next if events.empty?

        attended = @church.group_attendances.where(group_event_id: events.map(&:id), person_id: @person.id, attended: true)
                          .pluck(:group_event_id).to_set
        latest = events.last.starts_at.in_time_zone(zone)
        Row.new(kind: "group", title: key.name,
                subtitle: key.is_a?(Spirely::GroupType) ? ms.map { |m| m.group.name }.uniq.sort.join(", ") : nil,
                meetings: events.map { |e| { date: day_date(e.starts_at), attended: attended.include?(e.id) } },
                sort_key: [latest.wday, latest.hour * 60 + latest.min])
      end
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
