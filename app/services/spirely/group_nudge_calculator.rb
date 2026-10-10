module Spirely
  # Who has dropped off from their groups and classes (Small Groups,
  # 5ST-53): a current member who came to at least MIN_ATTENDED of the
  # group's last MEETINGS_CONSIDERED meetings and missed the last
  # MIN_MISSED_STREAK in a row.
  #
  # Only meetings where attendance was actually taken count (a meeting
  # with no attendance rows means nobody took it, not that nobody came),
  # and only meetings since the person joined.
  class GroupNudgeCalculator
    MEETINGS_CONSIDERED = 10
    MIN_ATTENDED        = 4
    MIN_MISSED_STREAK   = 2

    Result = Struct.new(:group, :person, :metrics, keyword_init: true)

    def initialize(church)
      @church = church
    end

    def call
      @church.groups.active.flat_map { |group| for_group(group) }
    end

    def for_group(group)
      meetings = group.events.held.past.where(id: Spirely::GroupAttendance.select(:group_event_id))
                      .order(starts_at: :desc).limit(MEETINGS_CONSIDERED).to_a.reverse
      return [] if meetings.size < MIN_MISSED_STREAK

      attended = Spirely::GroupAttendance.where(group_event_id: meetings.map(&:id), attended: true)
                                         .pluck(:group_event_id, :person_id).to_set
      zone = Spirely::ChurchTime.zone(@church)

      group.memberships.current.includes(:person).filter_map do |m|
        mine = meetings.select { |e| m.joined_at.nil? || e.starts_at >= m.joined_at }
        marks = mine.map { |e| attended.include?([e.id, m.person_id]) }
        count = marks.count(true)
        streak = marks.reverse.take_while { |a| !a }.size
        next if count < MIN_ATTENDED || streak < MIN_MISSED_STREAK

        Result.new(group: group, person: m.person, metrics: {
          "attended"      => count,
          "considered"    => marks.size,
          "missed_streak" => streak,
          "meetings"      => mine.zip(marks).map { |e, a| { "date" => e.starts_at.in_time_zone(zone).to_date.iso8601, "attended" => a } },
        })
      end
    end
  end
end
