module Spirely
  # Works out each active group's health from the synced Planning Center
  # Groups data (Small Groups module, 5ST-52). Deliberately only the flags
  # PCO's own reports don't give: PCO already shows attendance % and how
  # often groups meet, so there's no attendance or "not meeting" flag here.
  #
  # - no_leader:       no current leader membership
  # - shrinking:       current members down SHRINKING_THRESHOLD or more
  #                    versus TREND_WINDOW ago
  # - request_waiting: a pending join request older than REQUEST_WAIT
  #
  # Membership history comes from GroupMembership#joined_at (from PCO) and
  # #left_at (set by the sync when someone disappears), so "members then"
  # only counts departures the sync has seen — a church's first
  # TREND_WINDOW after enabling the module can under-report shrinking.
  class GroupHealthCalculator
    TREND_WINDOW        = 8.weeks
    SHRINKING_THRESHOLD = 0.25
    REQUEST_WAIT        = 7.days

    Flag = Struct.new(:key, :label, :detail, keyword_init: true)

    Health = Struct.new(:group, :leaders, :members_count, :members_then, :joined, :left,
                        :pending_requests, :waiting_requests, :flags, keyword_init: true) do
      def trend = members_count - members_then
      def needs_attention? = flags.any?
    end

    def initialize(church, now: Time.current)
      @church = church
      @now    = now
    end

    # One Health per active group, groups needing attention first.
    def call(groups = @church.groups.active)
      groups = groups.includes(:group_type, memberships: :person, applications: :person).to_a
      groups.map { |g| health_for(g) }
            .sort_by { |h| [h.needs_attention? ? 0 : 1, h.group.name.downcase] }
    end

    def health_for(group)
      cutoff      = @now - TREND_WINDOW
      memberships = group.memberships.to_a
      current     = memberships.select { |m| m.left_at.nil? }
      leaders     = current.select { |m| m.role == "leader" }.map(&:person)
      then_count  = memberships.count { |m| (m.joined_at.nil? || m.joined_at <= cutoff) && (m.left_at.nil? || m.left_at > cutoff) }
      joined      = current.select { |m| m.joined_at && m.joined_at > cutoff }
      left        = memberships.select { |m| m.left_at && m.left_at > cutoff }
      pending     = group.applications.select { |a| a.status == "pending" }.sort_by { |a| a.applied_at || @now }
      waiting     = pending.select { |a| a.applied_at && a.applied_at <= @now - REQUEST_WAIT }

      flags = []
      flags << Flag.new(key: "no_leader", label: "No leader", detail: "No current leader in Planning Center.") if leaders.empty?
      if then_count.positive? && (then_count - current.size).to_f / then_count >= SHRINKING_THRESHOLD
        flags << Flag.new(key: "shrinking", label: "Shrinking",
                          detail: "#{current.size} members now, down from #{then_count} over the last #{weeks} weeks.")
      end
      if (oldest = waiting.first)
        days = ((@now - oldest.applied_at) / 1.day).floor
        flags << Flag.new(key: "request_waiting", label: "Request waiting #{days} days",
                          detail: "#{oldest.person.full_name} asked to join #{days} days ago and hasn't heard back." +
                                  (waiting.size > 1 ? " #{waiting.size - 1} more waiting." : ""))
      end

      Health.new(group: group, leaders: leaders, members_count: current.size, members_then: then_count,
                 joined: joined, left: left, pending_requests: pending, waiting_requests: waiting, flags: flags)
    end

    private

    def weeks = TREND_WINDOW.in_weeks.to_i
  end
end
