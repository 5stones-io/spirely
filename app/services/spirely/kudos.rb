module Spirely
  # Kudos points (5ST-60) for one church: balances, the people points can
  # go to, and awarding or deducting by hand.
  #
  # Points belong to a Spirely::Person, but many people only exist on a
  # family record so far (a Person is created by the attendance and groups
  # syncs). So people are looked up across synced people, kids, guardians
  # and families' primary contacts, keyed by their Planning Center person
  # id, and a Person is created the first time someone gets points.
  class Kudos
    class Error < StandardError; end

    MAX_POINTS = 100_000

    # Someone points can go to. `person` is nil until they get their first points.
    Recipient = Struct.new(:pco_person_id, :person, :first_name, :last_name, :kid, :family, :grade, keyword_init: true) do
      def name = [first_name, last_name].compact_blank.join(" ")
    end

    def initialize(church)
      @church = church
    end

    def setting = KudosSetting.for(@church)

    # { balance:, earned:, deducted: } for one person (all zero for nil).
    def totals(person)
      return { balance: 0, earned: 0, deducted: 0 } unless person

      balance, earned, deducted = person.points_entries.pick(Arel.sql(<<~SQL.squish))
        COALESCE(SUM(points), 0),
        COALESCE(SUM(points) FILTER (WHERE points > 0), 0),
        COALESCE(-SUM(points) FILTER (WHERE points < 0), 0)
      SQL
      { balance: balance.to_i, earned: earned.to_i, deducted: deducted.to_i }
    end

    # Person id => balance.
    def balances(person_ids)
      return {} if person_ids.empty?
      @church.points_entries.where(person_id: person_ids).group(:person_id).sum(:points)
    end

    # A person's entries, newest first, each with the balance right after it.
    def history(person)
      person.points_entries.newest_first
            .select("spirely_points_entries.*, SUM(points) OVER (ORDER BY occurred_on, id) AS balance_after")
    end

    # People matching a name search, or with the given Planning Center ids.
    def recipients(query: nil, pco_ids: nil, limit: 25)
      found = {}
      add = lambda do |pco_id, attrs|
        next if pco_id.blank?
        # First source wins for each field: synced people, then kids,
        # guardians, and families' primary contacts.
        (found[pco_id] ||= Recipient.new(pco_person_id: pco_id)).tap do |r|
          attrs.each { |k, v| r[k] = v if r[k].nil? && !v.nil? }
        end
      end

      search(@church.people, "first_name", "last_name", query, pco_ids, limit).each do |p|
        add.(p.pco_person_id, person: p, first_name: p.first_name, last_name: p.last_name, kid: p.child)
      end
      search(@church.children.includes(:family), "first_name", "last_name", query, pco_ids, limit).each do |c|
        add.(c.pco_person_id, first_name: c.first_name, last_name: c.last_name, kid: true, family: c.family, grade: c.grade_display)
      end
      search(@church.guardians.includes(:family), "first_name", "last_name", query, pco_ids, limit).each do |g|
        add.(g.pco_person_id, first_name: g.first_name, last_name: g.last_name, kid: false, family: g.family)
      end
      search(@church.families, "primary_contact_first_name", "primary_contact_last_name", query, pco_ids, limit).each do |f|
        add.(f.pco_person_id, first_name: f.primary_contact_first_name, last_name: f.primary_contact_last_name, kid: false, family: f)
      end

      # A family record can match a search the synced Person's own name
      # doesn't (a different spelling), so attach Persons by id too.
      missing = found.values.reject(&:person).map(&:pco_person_id)
      @church.people.where(pco_person_id: missing).each { |p| found[p.pco_person_id].person = p } if missing.any?

      found.values.select { |r| r.first_name.present? }.sort_by { |r| r.name.downcase }.first(limit)
    end

    def recipient(pco_person_id)
      recipients(pco_ids: [pco_person_id.to_s], limit: 1).first
    end

    # Award (positive) or deduct (negative) points by hand. A deduction
    # can't take someone below zero.
    def award!(pco_person_id:, points:, note:, by_account:)
      points = Integer(points, exception: false)
      raise Error, "Enter a whole number of points." if points.nil? || points.zero?
      raise Error, "That's more than #{MAX_POINTS.to_fs(:delimited)} points at once." if points.abs > MAX_POINTS
      raise Error, "Add a reason — they'll see it in their history." if note.to_s.strip.empty?

      PointsEntry.transaction do
        person = person_for!(pco_person_id)
        person.lock!
        balance = totals(person)[:balance]
        if balance + points < 0
          raise Error, "#{person.first_name} only has #{balance.to_fs(:delimited)} #{balance == 1 ? "point" : "points"}."
        end

        @church.points_entries.create!(
          person: person, points: points, source: "manual", note: note.to_s.strip,
          awarded_by_account: by_account, awarded_by_name: by_account&.name.presence || by_account&.email,
          occurred_on: Spirely::ChurchTime.today(@church),
        )
      end
    end

    # The Person for this Planning Center id, created from their family
    # record if they haven't been synced as a Person yet.
    def person_for!(pco_person_id)
      found = recipient(pco_person_id) or raise ActiveRecord::RecordNotFound
      found.person || @church.people.create!(
        pco_person_id: found.pco_person_id, first_name: found.first_name, last_name: found.last_name, child: !!found.kid,
      )
    rescue ActiveRecord::RecordNotUnique
      @church.people.find_by!(pco_person_id: pco_person_id)
    end

    # Posts points for check-ins and group meetings attended (5ST-61) and
    # time served on Services plans (5ST-62) since the earning start date,
    # at the church's rates. Safe to run after every sync: each check-in,
    # meeting and plan pays a person at most once, and a rate of 0 posts
    # nothing. Points already posted stay put if PCO later drops the
    # record — they may have been spent. Returns how many entries it posted.
    def post_earned_points!
      return 0 unless @church.module_enabled?("kudos")

      setting = self.setting
      return 0 unless setting.earns_anything?

      zone  = ChurchTime.zone(@church)
      since = setting.earning_starts_on.in_time_zone(zone)
      rows  = checkin_rows(setting, since, zone) + group_rows(setting, since, zone) + service_rows(setting, since, zone)
      rows.each_slice(500).sum { |slice| PointsEntry.insert_all(slice).length }
    end

    # Claim a promo code for someone (5ST-61). Codes are case-insensitive
    # and each person can claim a code once.
    def claim_code!(code:, pco_person_id:)
      normalized = PromoCode.normalize(code) or raise Error, "Enter a code."

      PointsEntry.transaction do
        promo = @church.promo_codes.lock.find_by(code: normalized)
        raise Error, "That code doesn't match any we have. Check the spelling?" unless promo
        raise Error, "That code isn't active right now." if promo.turned_off?
        raise Error, "That code expired on #{promo.expires_on.to_fs(:long)}." if promo.expired?(ChurchTime.today(@church))
        raise Error, "That code has been used up." if promo.max_uses && promo.claims.count >= promo.max_uses

        person = person_for!(pco_person_id)
        raise Error, "#{person.first_name} already used this code." if promo.claims.exists?(person_id: person.id)

        @church.points_entries.create!(
          person: person, points: promo.points, source: "promo_code", source_type: promo.class.polymorphic_name,
          source_id: promo.id, note: promo.label, occurred_on: ChurchTime.today(@church),
        )
      end
    end

    # Check-Ins events seen in the last 16 weeks (the attendance sync's
    # window), most-attended first — what per-event rates are picked from.
    def checkin_events
      @church.attendances.where(checked_in_at: PcoAttendanceSyncJob::SYNC_WINDOW.ago..)
             .group(:pco_event_id).order(Arel.sql("COUNT(*) DESC"))
             .pluck(:pco_event_id, Arel.sql("MAX(event_name)"), Arel.sql("COUNT(*)"))
             .map { |id, name, count| { pco_event_id: id, event_name: name, check_ins: count } }
    end

    # The adults in a kid's household (for "their parents can see this").
    def parents_of(recipient)
      family = recipient.family
      return [] unless recipient.kid && family

      names = [[family.primary_contact_first_name, family.primary_contact_last_name].compact_blank.join(" ")]
      names += family.guardians.map { |g| [g.first_name, g.last_name].compact_blank.join(" ") }
      names.compact_blank.uniq
    end

    private

    # One entry per person per event per day, so a kid checked in twice by
    # mistake (or re-printed labels) only earns once. One-time guests are
    # skipped — they have no Planning Center profile to earn against.
    def checkin_rows(setting, since, zone)
      attendances = @church.attendances.where(one_time_guest: false, checked_in_at: since..).order(:id)
                           .pluck(:id, :person_id, :pco_event_id, :event_name, :checked_in_at)
      return [] if attendances.empty?

      paid = @church.points_entries.where(source_type: Attendance.polymorphic_name, source_id: attendances.map(&:first))
                    .pluck(:source_id).to_set

      attendances.group_by { |_, person_id, event_id, _, at| [person_id, event_id, at.in_time_zone(zone).to_date] }
                 .filter_map do |(person_id, event_id, day), same_day|
        next if same_day.any? { |id, *| paid.include?(id) }

        points = setting.points_for_checkin(event_id)
        next unless points.positive?

        id, _, _, event_name, _ = same_day.first
        entry_row(person_id, points, "checkin", Attendance.polymorphic_name, id, "Checked in · #{event_name}", day)
      end
    end

    # Keyed on the meeting rather than the attendance row, since the groups
    # sync replaces rows PCO no longer returns.
    def group_rows(setting, since, zone)
      return [] unless setting.group_points.positive?

      @church.group_attendances.where(attended: true).joins(group_event: :group).merge(GroupEvent.held)
             .where(spirely_group_events: { starts_at: since..Time.current })
             .where.not(PointsEntry.where(source_type: GroupEvent.polymorphic_name)
                                   .where("spirely_points_entries.source_id = spirely_group_attendances.group_event_id")
                                   .where("spirely_points_entries.person_id = spirely_group_attendances.person_id")
                                   .arel.exists)
             .pluck(:person_id, :group_event_id, "spirely_group_events.starts_at", "spirely_groups.name")
             .map do |person_id, event_id, starts_at, group_name|
        entry_row(person_id, setting.group_points, "group_attendance", GroupEvent.polymorphic_name, event_id,
                  "Attended #{group_name}", starts_at.in_time_zone(zone).to_date)
      end
    end

    # One entry per person per plan, once every time in the plan is over.
    # Keyed on the plan rather than the position, so someone on two teams
    # isn't paid twice for the same hours.
    def service_rows(setting, since, zone)
      return [] unless setting.earns_for_serving?

      plans = @church.service_plans.current.finished.where(sort_date: since..)
      rows  = @church.service_plan_people.where(plan: plans, status: "C")
                     .where.not(PointsEntry.where(source_type: ServicePlan.polymorphic_name)
                                           .where("spirely_points_entries.source_id = spirely_service_plan_people.plan_id")
                                           .where("spirely_points_entries.person_id = spirely_service_plan_people.person_id")
                                           .arel.exists)
                     .to_a
      return [] if rows.empty?

      by_id = ServicePlan.where(id: rows.map(&:plan_id)).includes(:service_type, :times).index_by(&:id)
      rows.group_by { |r| [r.plan_id, r.person_id] }.filter_map do |(plan_id, person_id), positions|
        plan    = by_id[plan_id]
        serving = plan.serving_for(positions, count_rehearsals: setting.count_rehearsals)
        points  = serving.flat ? setting.service_flat_points : (serving.hours * setting.service_hour_points).round
        next unless points.positive?

        note = ["Served · #{plan.name}", (hours_label(serving.hours) unless serving.flat)].compact.join(" · ")
        entry_row(person_id, points, "service", ServicePlan.polymorphic_name, plan_id, note,
                  plan.sort_date.in_time_zone(zone).to_date, details: { serving: serving_details(plan, serving, zone) })
      end
    end

    # Saved on the entry, so staff see what was paid for even after the
    # schedule or the settings change. Times are labeled in church time.
    def serving_details(plan, serving, zone)
      {
        plan: plan.name, dates: plan.dates, hours: serving.hours, flat: serving.flat,
        roles: serving.plan_people.map(&:role).compact_blank.uniq,
        times: serving.times.map do |t|
          { name: t.name, time_type: t.time_type, clock: t.starts_at.in_time_zone(zone).strftime("%-l:%M %p") }
        end,
      }
    end

    def hours_label(hours)
      n = ActiveSupport::NumberHelper.number_to_rounded(hours, precision: 2, strip_insignificant_zeros: true)
      "#{n} #{hours == 1 ? "hour" : "hours"}"
    end

    def entry_row(person_id, points, source, source_type, source_id, note, day, details: nil)
      { church_id: @church.id, person_id: person_id, points: points, source: source, source_type: source_type,
        source_id: source_id, note: note, occurred_on: day, details: details }
    end

    def search(scope, first_col, last_col, query, pco_ids, limit)
      table = scope.klass.table_name
      scope = scope.where.not(pco_person_id: [nil, ""])
      scope = scope.where(pco_person_id: pco_ids) if pco_ids
      if query.present?
        name = "COALESCE(#{table}.#{first_col}, '') || ' ' || COALESCE(#{table}.#{last_col}, '')"
        scope = scope.where("#{name} ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(query.strip)}%")
      end
      scope.limit(pco_ids ? pco_ids.size * 2 : limit)
    end
  end
end
