module Spirely
  # A person's recent attendance, one row per service or group they're part
  # of (5ST-75), for the staff Child sheet's attended/missed dots.
  #
  # - Check-ins: one row per Spirely::CheckInServices service (event + day +
  #   time, early times joined to the service whose window they fall in)
  #   the person has checked in for in the last 26 weeks.
  # - Groups: one row per group type the person is currently in (their
  #   class as the subtitle), counting meetings since they joined where
  #   attendance was taken — the same rule as GroupNudgeCalculator.
  #
  # Each row keeps its last MEETINGS_SHOWN, oldest first. Rows are ordered
  # through the week (Sunday first).
  class AttendanceHistory
    MEETINGS_SHOWN = 10

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

    # Check-in services this person has come to (Spirely::CheckInServices).
    def check_in_rows
      Spirely::CheckInServices.new(@church).for_person(@person.id).map do |svc|
        attended = svc.attended_dates(@person.id)
        Row.new(kind: "check_in", title: svc.title, subtitle: nil,
                meetings: svc.dates.last(MEETINGS_SHOWN).map { |d| { date: d, attended: attended.include?(d) } },
                sort_key: svc.sort_key)
      end
    end

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
  end
end
