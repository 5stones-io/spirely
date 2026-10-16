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

    # The adults in a kid's household (for "their parents can see this").
    def parents_of(recipient)
      family = recipient.family
      return [] unless recipient.kid && family

      names = [[family.primary_contact_first_name, family.primary_contact_last_name].compact_blank.join(" ")]
      names += family.guardians.map { |g| [g.first_name, g.last_name].compact_blank.join(" ") }
      names.compact_blank.uniq
    end

    private

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
