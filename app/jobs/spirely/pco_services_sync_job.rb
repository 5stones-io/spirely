module Spirely
  # Read-only mirror of Planning Center Services into Spirely::ServiceType /
  # ServicePlan / ServicePlanTime / ServicePlanPerson, so Kudos can pay
  # people for time served (5ST-62). Runs only for churches with Kudos on —
  # scheduled by the host app every few hours, plus Settings' "Sync Now".
  #
  # Only past plans are read: per service type, newest first, back to
  # HISTORY_WINDOW. Each plan's times and team members take one request
  # apiece, so they're only re-read while the plan is recent
  # (DETAIL_RECHECK) — schedulers often fix who served a few days late.
  #
  # Which times someone served comes from each scheduled person's own
  # `times` relationship, less any they declined; each plan time's
  # `assigned_teams` is the fallback. See ServicePlan#serving_for. (Don't
  # pass `fields[PlanTime]` here: PCO treats it as "only these fields" and
  # drops the relationships.)
  #
  # A 403 means this church's PCO connection can't read Services (a PAT
  # user without Services access). That's recorded on SyncSetting for
  # Settings' notice rather than raised, since retrying won't help.
  class PcoServicesSyncJob < ApplicationJob
    include Spirely::PcoFetching

    BASE           = "/services/v2"
    HISTORY_WINDOW = 26.weeks
    DETAIL_RECHECK = 14.days

    def perform(church_id)
      church = Church.find(church_id)
      return unless church.module_enabled?("kudos")
      return unless church.church_integration&.pco_connected?

      @church   = church
      @client   = Spirely::PcoClient.new(church.church_integration)
      @people   = {}
      settings  = church.sync_setting || church.create_sync_setting!

      sync_service_types
      church.service_types.current.find_each { |type| sync_plans(type) }
      plans_needing_details.find_each { |plan| sync_plan_details(plan) }

      settings.update!(services_last_synced_at: Time.current, services_access_denied_at: nil)
      Spirely::KudosEarningJob.perform_later(church.id)
    rescue Spirely::PcoApiError => e
      raise unless e.status == 403

      Rails.logger.warn("[Spirely] PcoServicesSyncJob: PCO denied Services access for church #{church_id}")
      settings&.update!(services_access_denied_at: Time.current)
    rescue Spirely::PcoError => e
      Rails.logger.error("[Spirely] PcoServicesSyncJob failed for church #{church_id}: #{e.message}")
      raise
    end

    private

    def sync_service_types
      seen = fetch_all("#{BASE}/service_types").map do |pco|
        type = @church.service_types.find_or_initialize_by(pco_service_type_id: pco["id"])
        type.assign_attributes(name: pco.dig("attributes", "name").presence || "Untitled", removed_at: nil)
        save_if_changed(type)
        pco["id"]
      end
      @church.service_types.current.where.not(pco_service_type_id: seen).update_all(removed_at: Time.current)
    end

    # Newest first, stopping once a page reaches past the window.
    def sync_plans(type)
      from  = HISTORY_WINDOW.ago
      plans = fetch_all("#{BASE}/service_types/#{type.pco_service_type_id}/plans",
                        { "filter" => "past", "order" => "-sort_date" }) do |page|
        oldest = page.last&.dig("attributes", "sort_date")
        oldest.nil? || Time.zone.parse(oldest) >= from
      end

      seen = plans.filter_map do |pco|
        attrs     = pco["attributes"]
        sort_date = attrs["sort_date"] && Time.zone.parse(attrs["sort_date"])
        next unless sort_date && sort_date >= from

        plan = @church.service_plans.find_or_initialize_by(pco_plan_id: pco["id"])
        plan.assign_attributes(service_type: type, title: attrs["title"], series_title: attrs["series_title"],
                               dates: attrs["dates"], sort_date: sort_date, removed_at: nil)
        save_if_changed(plan)
        pco["id"]
      end
      type.plans.current.where(sort_date: from..Time.current).where.not(pco_plan_id: seen)
          .update_all(removed_at: Time.current)
    end

    def plans_needing_details
      @church.service_plans.current.where(sort_date: HISTORY_WINDOW.ago..Time.current)
             .where("people_synced_at IS NULL OR sort_date >= ?", DETAIL_RECHECK.ago)
             .includes(:service_type)
    end

    def sync_plan_details(plan)
      path = "#{BASE}/service_types/#{plan.service_type.pco_service_type_id}/plans/#{plan.pco_plan_id}"
      ends = sync_times(plan, path)
      sync_team_members(plan, path)
      plan.update!(ends_at: ends, people_synced_at: Time.current)
    end

    # Returns when the plan's last time ends.
    def sync_times(plan, path)
      seen = fetch_all("#{path}/plan_times").filter_map do |pco|
        attrs = pco["attributes"]
        teams = pco.dig("relationships", "assigned_teams")
        next unless attrs["starts_at"] && attrs["ends_at"]

        time = plan.times.find_or_initialize_by(pco_plan_time_id: pco["id"])
        time.assign_attributes(
          church: @church, name: attrs["name"], starts_at: attrs["starts_at"], ends_at: attrs["ends_at"],
          time_type: ServicePlanTime::TYPES.include?(attrs["time_type"]) ? attrs["time_type"] : "other",
          team_ids: teams && Array(teams["data"]).map { |d| d["id"].to_s },
        )
        save_if_changed(time)
        time
      end
      plan.times.where.not(id: seen.map(&:id)).delete_all
      seen.map(&:ends_at).max
    end

    def sync_team_members(plan, path)
      response = fetch_all("#{path}/team_members", { "include" => "person,team,declined_plan_times" }, with_included: true)
      people = index_included(response[:included], "Person")
      teams  = index_included(response[:included], "Team")

      seen = response[:data].filter_map do |pco|
        attrs  = pco["attributes"]
        rels   = pco["relationships"] || {}
        status = ServicePlanPerson.normalize_status(attrs["status"])
        person_id = rels.dig("person", "data", "id")
        next unless status && person_id

        person  = upsert_person(person_id, people[person_id], attrs["name"])
        team_id = rels.dig("team", "data", "id")
        times   = rels["times"]
        row = plan.plan_people.find_or_initialize_by(pco_plan_person_id: pco["id"])
        row.assign_attributes(
          church: @church, person: person, status: status, pco_team_id: team_id,
          team_name: teams[team_id]&.dig("attributes", "name"), position_name: attrs["team_position_name"],
          declined_time_ids: Array(rels.dig("declined_plan_times", "data")).map { |d| d["id"].to_s },
          time_ids: times && Array(times["data"]).map { |d| d["id"].to_s },
        )
        save_if_changed(row)
        row.id
      end
      plan.plan_people.where.not(id: seen).delete_all
    end

    # Services' Person carries little beyond a name, so this only fills in
    # names for people Spirely hasn't seen yet — the People and Check-Ins
    # syncs own everything else.
    def upsert_person(pco_id, pco, fallback_name)
      return @people[pco_id] if @people.key?(pco_id)

      person = @church.people.find_or_initialize_by(pco_person_id: pco_id)
      if person.new_record?
        attrs = pco&.dig("attributes") || {}
        first, last = fallback_name.to_s.split(" ", 2)
        person.first_name = attrs["first_name"].presence || first.presence || "Unknown"
        person.last_name  = attrs["last_name"].presence || last
        person.pco_last_synced_at = Time.current
        person.save!
      end
      @people[pco_id] = person
    end
  end
end
