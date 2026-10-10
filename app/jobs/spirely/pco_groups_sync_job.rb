module Spirely
  # Read-only mirror of Planning Center Groups into Spirely::GroupType /
  # Group / GroupMembership / GroupEvent / GroupAttendance /
  # GroupApplication (Small Groups module, 5ST-51). Runs for churches with
  # any groups-using module on (Church#uses_groups?) — scheduled by the
  # host app every few hours, plus Settings' "Sync Now".
  #
  # PCO Groups has no org-wide memberships/attendance endpoints, so this is
  # one request per group for memberships and events, plus one per meeting
  # for attendance. To keep that bounded, attendance is only fetched for
  # each group's last ATTENDANCE_MEETINGS past meetings, and only re-fetched
  # once synced if the meeting is within ATTENDANCE_RECHECK (leaders often
  # submit or fix attendance a few days late).
  #
  # Nothing removed in PCO is hard-deleted except join requests: groups
  # and meetings get removed_at, memberships get left_at, so group health
  # and drop-off checks keep their history.
  #
  # A 403 means this church's PCO connection can't read Groups (an OAuth
  # connection made before the `groups` scope was added, or a PAT user
  # without Groups access). That's recorded on SyncSetting for Settings'
  # reconnect notice rather than raised, since retrying won't help.
  class PcoGroupsSyncJob < ApplicationJob
    BASE                = "/groups/v2"
    HISTORY_WINDOW      = 26.weeks
    UPCOMING_WINDOW     = 12.weeks
    ATTENDANCE_MEETINGS = 10
    ATTENDANCE_RECHECK  = 14.days
    RATE_LIMIT_PAUSE    = 20 # seconds — PCO allows ~100 requests per 20s
    MAX_RATE_RETRIES    = 3

    def perform(church_id)
      church = Church.find(church_id)
      return unless church.uses_groups?
      return unless church.church_integration&.pco_connected?

      @church   = church
      @client   = Spirely::PcoClient.new(church.church_integration)
      @people   = {}
      settings  = church.sync_setting || church.create_sync_setting!

      sync_group_types
      sync_groups
      church.groups.active.find_each do |group|
        sync_memberships(group)
        sync_events(group)
        sync_attendance(group)
      end
      sync_applications

      settings.update!(groups_last_synced_at: Time.current, groups_access_denied_at: nil)
      # Fresh attendance in hand — refresh attendance follow-ups (5ST-53).
      Spirely::GroupNudgeSyncJob.perform_later(church.id)
    rescue Spirely::PcoApiError => e
      raise unless e.status == 403

      Rails.logger.warn("[Spirely] PcoGroupsSyncJob: PCO denied Groups access for church #{church_id}")
      settings&.update!(groups_access_denied_at: Time.current)
    rescue Spirely::PcoError => e
      Rails.logger.error("[Spirely] PcoGroupsSyncJob failed for church #{church_id}: #{e.message}")
      raise
    end

    private

    def sync_group_types
      seen = fetch_all("#{BASE}/group_types").map do |pco|
        type = @church.group_types.find_or_initialize_by(pco_group_type_id: pco["id"])
        type.assign_attributes(name: pco.dig("attributes", "name").presence || "Untitled",
                               color: pco.dig("attributes", "color"), removed_at: nil)
        save_if_changed(type)
        pco["id"]
      end
      @church.group_types.current.where.not(pco_group_type_id: seen).update_all(removed_at: Time.current)
    end

    def sync_groups
      types = @church.group_types.pluck(:pco_group_type_id, :id).to_h
      response = fetch_all("#{BASE}/groups", { "where[archive_status]" => "include", "include" => "location" },
                           with_included: true)
      locations = index_included(response[:included], "Location")

      seen = response[:data].map do |pco|
        attrs    = pco["attributes"]
        location = locations[pco.dig("relationships", "location", "data", "id")]
        group = @church.groups.find_or_initialize_by(pco_group_id: pco["id"])
        group.assign_attributes(
          name:              attrs["name"].presence || "Untitled group",
          description:       attrs["description_as_plain_text"],
          schedule_text:     attrs["schedule"],
          memberships_count: attrs["memberships_count"],
          church_center_url: attrs["public_church_center_web_url"],
          archived_at:       attrs["archived_at"],
          group_type_id:     types[pco.dig("relationships", "group_type", "data", "id")],
          location_name:     location&.dig("attributes", "name"),
          location_address:  location&.dig("attributes", "full_formatted_address"),
          removed_at:        nil,
          pco_last_synced_at: Time.current
        )
        save_if_changed(group)
        pco["id"]
      end
      @church.groups.where(removed_at: nil).where.not(pco_group_id: seen).update_all(removed_at: Time.current)
    end

    def sync_memberships(group)
      response = fetch_all("#{BASE}/groups/#{group.pco_group_id}/memberships", { "include" => "person" },
                           with_included: true)
      people = index_included(response[:included], "Person")

      seen = response[:data].filter_map do |pco|
        person = upsert_person(people[pco.dig("relationships", "person", "data", "id")])
        next unless person

        membership = group.memberships.find_or_initialize_by(church: @church, pco_membership_id: pco["id"])
        membership.assign_attributes(person: person,
                                     role: pco.dig("attributes", "role") == "leader" ? "leader" : "member",
                                     joined_at: pco.dig("attributes", "joined_at"), left_at: nil)
        save_if_changed(membership)
        pco["id"]
      end
      group.memberships.current.where.not(pco_membership_id: seen).update_all(left_at: Time.current)
    end

    def sync_events(group)
      from = HISTORY_WINDOW.ago
      to   = UPCOMING_WINDOW.from_now
      events = fetch_all("#{BASE}/groups/#{group.pco_group_id}/events",
                         { "where[starts_at][gte]" => from.iso8601, "where[starts_at][lte]" => to.iso8601 })

      seen = events.map do |pco|
        attrs = pco["attributes"]
        event = group.events.find_or_initialize_by(church: @church, pco_event_id: pco["id"])
        event.assign_attributes(name: attrs["name"], starts_at: attrs["starts_at"], ends_at: attrs["ends_at"],
                                canceled: attrs["canceled"] == true, removed_at: nil)
        save_if_changed(event)
        pco["id"]
      end
      group.events.where(removed_at: nil, starts_at: from..to)
           .where.not(pco_event_id: seen).update_all(removed_at: Time.current)
    end

    def sync_attendance(group)
      recent = group.events.held.past.order(starts_at: :desc).limit(ATTENDANCE_MEETINGS)
      recent.each do |event|
        next if event.attendance_synced_at && event.starts_at < ATTENDANCE_RECHECK.ago

        response = fetch_all("#{BASE}/events/#{event.pco_event_id}/attendances", { "include" => "person" },
                             with_included: true)
        people = index_included(response[:included], "Person")

        seen_person_ids = response[:data].filter_map do |pco|
          person = upsert_person(people[pco.dig("relationships", "person", "data", "id")])
          next unless person

          attendance = event.attendances.find_or_initialize_by(church: @church, person: person)
          attendance.assign_attributes(attended: pco.dig("attributes", "attended") == true,
                                       role: pco.dig("attributes", "role"))
          save_if_changed(attendance)
          person.id
        end
        event.attendances.where.not(person_id: seen_person_ids).delete_all
        event.update!(attendance_synced_at: Time.current)
      end
    end

    def sync_applications
      groups = @church.groups.pluck(:pco_group_id, :id).to_h
      response = fetch_all("#{BASE}/group_applications", { "where[status]" => "pending", "include" => "person" },
                           with_included: true)
      people = index_included(response[:included], "Person")

      seen = response[:data].filter_map do |pco|
        group_id = groups[pco.dig("relationships", "group", "data", "id")]
        person   = upsert_person(people[pco.dig("relationships", "person", "data", "id")])
        next unless group_id && person

        application = @church.group_applications.find_or_initialize_by(pco_application_id: pco["id"])
        application.assign_attributes(group_id: group_id, person: person,
                                      status: pco.dig("attributes", "status") || "pending",
                                      applied_at: pco.dig("attributes", "applied_at"),
                                      message: pco.dig("attributes", "message"))
        save_if_changed(application)
        pco["id"]
      end
      @church.group_applications.where.not(pco_application_id: seen).delete_all
    end

    # Groups' included Person carries name, child flag and contact info.
    # Names follow PCO; email/phone only fill blanks, so this never fights
    # the People/Check-Ins syncs. The email matters: leaders and members
    # sign in by magic link, and current_person finds them by email.
    def upsert_person(pco)
      return nil unless pco
      return @people[pco["id"]] if @people.key?(pco["id"])

      attrs  = pco["attributes"] || {}
      person = @church.people.find_or_initialize_by(pco_person_id: pco["id"])
      person.first_name = attrs["first_name"].presence || person.first_name.presence || "Unknown"
      person.last_name  = attrs["last_name"] if attrs["last_name"].present?
      person.child      = true if attrs["child"] == true
      person.email    ||= primary(attrs["email_addresses"], "address")
      person.phone    ||= primary(attrs["phone_numbers"], "number")
      person.pco_last_synced_at = Time.current if person.new_record?
      save_if_changed(person)
      @people[pco["id"]] = person
    end

    def primary(entries, key)
      list = Array(entries)
      (list.find { |e| e["primary"] } || list.first)&.dig(key).presence
    end

    def save_if_changed(record)
      record.save! if record.new_record? || record.changed?
      record
    end

    def index_included(included, type)
      Array(included).select { |r| r["type"] == type }.index_by { |r| r["id"] }
    end

    # Follows links.next like PcoClient#paginate, but retries a 429 on the
    # page that hit it instead of failing the whole sync.
    def fetch_all(path, params = {}, with_included: false)
      data, included = [], []
      query = params.merge("per_page" => Spirely::PcoClient::PAGE_SIZE)

      loop do
        page = get_with_retry(path, query)
        data.concat(Array(page["data"]))
        included.concat(Array(page["included"]))

        next_link = page.dig("links", "next").presence
        break unless next_link

        uri   = URI.parse(next_link)
        path  = uri.path
        query = URI.decode_www_form(uri.query.to_s).to_h
      end

      with_included ? { data: data, included: included } : data
    end

    def get_with_retry(path, query, attempt: 0)
      @client.get(path, query)
    rescue Spirely::PcoApiError => e
      raise unless e.status == 429 && attempt < MAX_RATE_RETRIES

      sleep RATE_LIMIT_PAUSE
      get_with_retry(path, query, attempt: attempt + 1)
    end
  end
end
