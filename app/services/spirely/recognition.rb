module Spirely
  # Kudos recognition for one church (5ST-64): shout-outs, the leader
  # allowance, the recognition feed and leaderboards.
  #
  # Who can see a shout-out (#visible_to?):
  #   * staff see everything, hidden ones included
  #   * a shout-out to a kid: only the sender and the kid's parents
  #   * a private one: only the sender and the recipient
  #   * a public one to an adult: anyone signed in, until staff hide it
  class Recognition
    # Whoever is looking: their account, their own Person (if any), whether
    # they're staff, and the Person ids of their own kids.
    Viewer = Struct.new(:account, :person, :staff, :kid_person_ids, keyword_init: true) do
      def name = person&.full_name.presence || account&.name.presence || account&.email
    end

    LEADERBOARD_SIZE = 10
    FEED_SIZE = 30

    def initialize(church)
      @church = church
      @kudos  = Kudos.new(church)
    end

    def setting = @kudos.setting

    # Groups leaders and Services team leaders get the monthly allowance.
    def leader?(person)
      return false unless person

      @church.group_memberships.current.leaders.joins(:group).merge(Group.active).exists?(person_id: person.id) ||
        @church.service_team_leaders.exists?(person_id: person.id)
    end

    # Points a leader has left to give this month; nil for non-leaders.
    # Unused allowance doesn't roll over.
    def allowance_left(person)
      return nil unless leader?(person) && setting.leader_allowance.positive?

      given = @church.shout_outs.where(from_person: person, points_from: "allowance", created_at: this_month).sum(:points)
      [setting.leader_allowance - given, 0].max
    end

    def give!(viewer:, to_pco_person_id:, message:, visibility: "public", points: 0)
      message = message.to_s.strip
      raise Kudos::Error, "Say what you're thanking them for." if message.empty?
      raise Kudos::Error, "Keep it under #{ShoutOut::MAX_MESSAGE} characters." if message.length > ShoutOut::MAX_MESSAGE
      raise Kudos::Error, "Pick public or private." unless ShoutOut::VISIBILITIES.include?(visibility)

      points = Integer(points.presence || 0, exception: false)
      raise Kudos::Error, "Points must be a whole number." if points.nil? || points.negative?

      to = @kudos.person_for!(to_pco_person_id)
      raise Kudos::Error, "You can't send yourself a shout-out." if viewer.person && to.id == viewer.person.id

      ShoutOut.transaction do
        if points.positive?
          raise Kudos::Error, "Only group and team leaders can give points with a shout-out." unless leader?(viewer.person)

          viewer.person.lock!
          left = allowance_left(viewer.person).to_i
          raise Kudos::Error, "You have #{left.to_fs(:delimited)} #{left == 1 ? "point" : "points"} left to give this month." if points > left
        end

        shout = @church.shout_outs.create!(
          from_account: viewer.account, from_person: viewer.person, from_name: viewer.name, to_person: to,
          message: message, visibility: visibility, points: points, points_from: ("allowance" if points.positive?),
        )
        attach_points!(shout, points, by_account: viewer.account, by_name: viewer.name) if points.positive?
        shout
      end
    end

    # Staff add points to a shout-out that has none.
    def add_points!(shout, points:, by_account:)
      points = Integer(points, exception: false)
      raise Kudos::Error, "Enter a whole number of points." unless points&.positive?
      raise Kudos::Error, "That's more than #{Kudos::MAX_POINTS.to_fs(:delimited)} points at once." if points > Kudos::MAX_POINTS

      shout.with_lock do
        raise Kudos::Error, "That shout-out already came with points." if shout.points.positive?

        shout.update!(points: points, points_from: "staff")
        attach_points!(shout, points, by_account: by_account, by_name: by_account.name.presence || by_account.email)
      end
      shout
    end

    def hide!(shout, hidden:, by_account:)
      shout.update!(hidden_at: hidden ? (shout.hidden_at || Time.current) : nil,
                    hidden_by_name: hidden ? (by_account.name.presence || by_account.email) : nil)
      shout
    end

    # A public shout-out for a staff award shared on the feed (5ST-64),
    # pointing at the award's points entry.
    def share_award!(entry, by_account:)
      @church.shout_outs.create!(
        from_account: by_account, from_name: entry.awarded_by_name.presence || "Church staff", to_person: entry.person,
        message: entry.note, visibility: "public", points: entry.points, points_from: "staff", points_entry: entry,
      )
    end

    def visible_to?(shout, viewer)
      return true if viewer.staff
      return false if shout.hidden?

      sender = viewer.account && shout.from_account_id == viewer.account.id
      if shout.to_kid?
        sender || viewer.kid_person_ids.include?(shout.to_person_id)
      elsif !shout.public?
        sender || (viewer.person && shout.to_person_id == viewer.person.id)
      else
        true
      end
    end

    # Public shout-outs to adults, newest first.
    def feed(limit: FEED_SIZE)
      @church.shout_outs.shown.where(visibility: "public").joins(:to_person)
             .where(spirely_people: { child: [false, nil] }).newest_first.includes(:to_person).limit(limit)
    end

    # What the viewer sent, and what they or their kids received.
    def mine(viewer, limit: FEED_SIZE)
      received_ids = [viewer.person&.id, *viewer.kid_person_ids].compact
      scope = @church.shout_outs.where(to_person_id: received_ids)
      scope = scope.or(@church.shout_outs.where(from_account: viewer.account)) if viewer.account
      scope.newest_first.includes(:to_person).limit(limit).select { |s| visible_to?(s, viewer) }
    end

    # Top earners for the month or year, adults and kids on separate
    # boards, optionally within one group or Services team. Refunds aren't
    # earnings, and people who opted out are left off.
    def leaderboard(period: "month", kids: false, group_id: nil, pco_team_id: nil, limit: LEADERBOARD_SIZE)
      range  = period == "year" ? this_year_days : this_month_days
      people = @church.people.where(child: kids ? true : [false, nil], kudos_leaderboard_opt_out: false)
      people = people.where(id: @church.group_memberships.current.where(group_id: group_id).select(:person_id)) if group_id
      if pco_team_id
        people = people.where(id: @church.service_plan_people.where(pco_team_id: pco_team_id).select(:person_id))
      end

      totals = @church.points_entries.where(person_id: people.select(:id), occurred_on: range)
                      .where("points > 0").where.not(source: "refund")
                      .group(:person_id).order(Arel.sql("SUM(points) DESC")).limit(limit).sum(:points)
      names = @church.people.where(id: totals.keys).index_by(&:id)
      totals.each_with_index.map do |(person_id, points), i|
        { rank: i + 1, name: board_name(names[person_id]), points: points }
      end
    end

    # What a leaderboard can be narrowed to: active groups, and Services
    # teams people served on in the last half year.
    def leaderboard_scopes
      groups = @church.groups.active.order(:name).pluck(:id, :name).map { |id, name| { kind: "group", id: id.to_s, name: name } }
      teams  = @church.service_plan_people.joins(:plan).where(spirely_service_plans: { sort_date: 26.weeks.ago.. })
                      .where.not(pco_team_id: nil).distinct.pluck(:pco_team_id, :team_name)
                      .sort_by { |_, name| name.to_s }
                      .map { |id, name| { kind: "team", id: id, name: name.presence || "Team" } }
      groups + teams
    end

    private

    def attach_points!(shout, points, by_account:, by_name:)
      entry = @church.points_entries.create!(
        person: shout.to_person, points: points, source: "shout_out", source_type: ShoutOut.polymorphic_name,
        source_id: shout.id, note: "Shout-out from #{shout.from_name}", awarded_by_account: by_account,
        awarded_by_name: by_name, occurred_on: ChurchTime.today(@church),
      )
      shout.update!(points_entry: entry)
    end

    # "Emma J." — first name and last initial on every board.
    def board_name(person)
      return "Someone" unless person

      [person.first_name, person.last_name.to_s[0]&.then { |c| "#{c}." }].compact_blank.join(" ")
    end

    def zone = ChurchTime.zone(@church)
    def this_month = Time.current.in_time_zone(zone).all_month
    def this_month_days = ChurchTime.today(@church).all_month
    def this_year_days = ChurchTime.today(@church).all_year
  end
end
