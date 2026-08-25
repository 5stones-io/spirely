module Spirely
  # Caches PCO check-in data locally as Spirely::Attendance, normalized per
  # the product spec's Section 2 ("Cache PCO attendance/check-in data
  # locally... not a raw PCO passthrough"). Always re-fetches a rolling
  # trailing window rather than tracking incremental sync state - church-
  # scale attendance volume (hundreds, not millions, per the Attendance
  # Nudge spec) makes this cheap, and find_or_create_by! on pco_check_in_id
  # makes re-running safe.
  class PcoAttendanceSyncJob < ApplicationJob
    # Covers the 8-12 week baseline window the nudge computation needs
    # (spec Section 3.1) with headroom.
    SYNC_WINDOW = 16.weeks

    def perform(church_id)
      church = Church.find(church_id)
      return unless church.church_integration&.pco_connected?

      client = Spirely::PcoClient.new(church.church_integration)

      response = client.paginate(
        "/check-ins/v2/check_ins",
        include: "person,event_period,check_in_times",
        "where[created_at][gte]": SYNC_WINDOW.ago.iso8601
      )

      check_ins = response["data"]
      included  = response["included"]

      people          = index_by_id(included, "Person")
      event_periods   = index_by_id(included, "EventPeriod")
      events          = resolve_events(client, event_periods)
      check_in_times  = index_by_check_in_id(included)
      locations       = resolve_locations(client)

      check_ins.each { |ci| sync_check_in(church, ci, people, event_periods, events, check_in_times, locations) }

      Rails.logger.info("[Spirely] PcoAttendanceSyncJob complete for church #{church_id} — #{check_ins.size} check-ins")
    rescue Spirely::PcoError => e
      Rails.logger.error("[Spirely] PcoAttendanceSyncJob failed for church #{church_id}: #{e.message}")
      raise
    end

    private

    # Event isn't directly related to CheckIn (only via EventPeriod), and
    # isn't returned by a plain `include=event_period` - resolved with a
    # second, batched request rather than assuming PCO supports the dotted
    # `include=event_period.event` (untested against the real API).
    def resolve_events(client, event_periods)
      event_ids = event_periods.values.filter_map { |ep| ep.dig("relationships", "event", "data", "id") }.uniq
      return {} if event_ids.empty?

      response = client.get("/check-ins/v2/events", { "where[id]" => event_ids.join(",") })
      index_by_id(response["data"], "Event")
    end

    # `where[id]` on this endpoint doesn't actually filter (confirmed
    # directly against the real API — it silently returns every location,
    # paginated, regardless of the filter) - a church's location/room list
    # is small (dozens, not thousands) and slow-changing, so fetching all
    # of them once per sync via get_all and indexing locally is simpler
    # and more correct than trying to make the filter work.
    def resolve_locations(client)
      index_by_id(client.get_all("/check-ins/v2/locations"), "Location")
    end

    # CheckInTime isn't directly embedded on CheckIn - it's a separate
    # included resource linked back via relationships.check_in.data.id,
    # itself pointing at a Location. A check-in can in principle have more
    # than one CheckInTime; only the first is used (kids ministry check-ins
    # are effectively always single-room in practice).
    def index_by_check_in_id(included)
      Array(included).select { |r| r["type"] == "CheckInTime" }
                     .group_by { |r| r.dig("relationships", "check_in", "data", "id") }
                     .transform_values(&:first)
    end

    def sync_check_in(church, check_in, people, event_periods, events, check_in_times, locations)
      attrs           = check_in["attributes"]
      pco_person_id   = check_in.dig("relationships", "person", "data", "id")
      event_period_id = check_in.dig("relationships", "event_period", "data", "id")
      return unless pco_person_id && event_period_id

      pco_event_id = event_periods.dig(event_period_id, "relationships", "event", "data", "id")
      return unless pco_event_id

      person = sync_person(church, people[pco_person_id])
      return unless person

      location_id = check_in_times.dig(check_in["id"], "relationships", "location", "data", "id")

      attendance = church.attendances.find_or_initialize_by(pco_check_in_id: check_in["id"])
      attendance.assign_attributes(
        person:         person,
        pco_event_id:   pco_event_id,
        event_name:     events.dig(pco_event_id, "attributes", "name") || "Unknown service",
        checked_in_at:  attrs["created_at"],
        checked_out_at: attrs["checked_out_at"],
        medical_notes:  attrs["medical_notes"],
        pco_location_id: location_id,
        location_name:   locations.dig(location_id, "attributes", "name"),
        # PCO's real API returns Title Case ("Regular", "Volunteer"), not
        # the lowercase this app's own Attendance::KINDS enum uses —
        # confirmed directly against production data (every real check-in
        # was failing Attendance's kind validation until this normalized).
        kind:           attrs["kind"].presence&.downcase || "regular",
        one_time_guest: attrs["one_time_guest"] || false
      )
      # Re-syncing an already-synced check-in is the only way checked_out_at
      # (and any other PCO-side edit, like medical_notes) ever reaches this
      # app — find_or_create_by would silently skip existing rows forever.
      attendance.save! if attendance.new_record? || attendance.changed?
    rescue => e
      Rails.logger.error("[Spirely] Failed to sync check-in pco_id=#{check_in["id"]} church=#{church.id}: #{e.message}")
    end

    # Built directly from the check-ins response's included Person data
    # (already fetched via include=person) rather than a per-person PCO
    # call - avoids N+1 API calls against a potentially large check-in batch.
    def sync_person(church, pco_person)
      return nil unless pco_person

      attrs = pco_person["attributes"]
      person = church.people.find_or_initialize_by(pco_person_id: pco_person["id"])
      person.assign_attributes(
        first_name: attrs["first_name"] || "Unknown",
        last_name:  attrs["last_name"],
        # PCO's own child/adult classification is sometimes just wrong —
        # confirmed on real production data (a child born 2020, actively
        # checking in, flagged "Adult" in PCO). We're processing a real
        # check-in for this exact person right now, so trust their
        # birthdate over PCO's own flag when the two disagree.
        child:      attrs["child"] || likely_a_minor?(attrs["birthdate"]),
        birthdate:  attrs["birthdate"],
        pco_last_synced_at: Time.current
      )
      person.save! if person.new_record? || person.changed?
      person
    end

    def index_by_id(records, type)
      Array(records).select { |r| r["type"] == type }.index_by { |r| r["id"] }
    end

    CLEARLY_MINOR_AGE = 18

    def likely_a_minor?(birthdate_str)
      return false if birthdate_str.blank?

      bd    = Date.parse(birthdate_str)
      today = Date.current
      age   = today.year - bd.year
      age  -= 1 if today.month < bd.month || (today.month == bd.month && today.day < bd.day)
      age < CLEARLY_MINOR_AGE
    rescue ArgumentError
      false
    end
  end
end
