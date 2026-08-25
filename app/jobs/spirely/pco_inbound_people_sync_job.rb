module Spirely
  # Runs for one specific church at a time (unlike self-hosted's single
  # global job) — spirely-cloud has many churches, each with their own PCO
  # connection and sync settings.
  class PcoInboundPeopleSyncJob < ApplicationJob
    def perform(church_id)
      church = Church.find(church_id)
      settings = church.sync_setting
      return unless settings&.inbound_people_sync?
      return unless church.church_integration&.pco_connected?

      client = Spirely::PcoClient.new(church.church_integration)
      ministry_tag = settings.effective_ministry_tag

      tagged_hh_ids = tagged_household_ids(client, ministry_tag) if ministry_tag.present?

      if tagged_hh_ids&.empty?
        Rails.logger.warn("[Spirely] PcoInboundPeopleSyncJob (church #{church_id}): tag '#{ministry_tag}' matched no people — sync aborted")
        return
      end

      response = client.paginate(
        "/people/v2/people",
        include: "households,emails,phone_numbers,addresses"
      )

      people    = response["data"]
      included  = response["included"]

      if tagged_hh_ids
        people = people.select { |p|
          hh_id = p.dig("relationships", "households", "data", 0, "id")
          tagged_hh_ids.include?(hh_id)
        }
      end

      households = index_by_id(included, "Household")
      emails     = group_by_person(included, "Email")
      phones     = group_by_person(included, "PhoneNumber")
      addresses  = group_by_person(included, "Address")

      checked_in_pco_ids = checked_in_pco_ids_for(church, people)
      adults   = people.reject { |p| treat_as_child?(p, checked_in_pco_ids) }
      children = people.select { |p| treat_as_child?(p, checked_in_pco_ids) }

      # Grouped by household, not synced one-adult-at-a-time — a household
      # can have more than one adult (confirmed against real production
      # data: a second parent had zero local representation at all, since
      # the old per-adult sync only ever wrote one Family record per
      # household and treated whichever adult it saw as *the* primary
      # contact, independently, with no household-level grouping). One
      # adult still becomes the Family's own primary contact; every other
      # adult in the same household becomes a Guardian instead, per
      # Chad's explicit call — Quick-Add stays single-parent by design,
      # PCO sync should bring over everyone.
      # Grouped by a key that falls back to the person's own id when
      # there's no household relationship at all — without that fallback,
      # every household-less adult would group together under a shared
      # `nil` key and get treated as one big unrelated "household." The
      # real (possibly still nil) household_id is recovered separately
      # below, not the synthetic grouping key — storing a person id in
      # pco_household_id would be its own kind of wrong.
      adults.group_by { |p| p.dig("relationships", "households", "data", 0, "id") || "solo-#{p["id"]}" }
            .each_value { |household_adults|
              household_id = household_adults.first.dig("relationships", "households", "data", 0, "id")
              sync_household(church, household_id, household_adults, households, emails, phones, addresses)
            }
      children.each { |p| sync_child(church, p, households) }

      settings.update!(last_synced_at: Time.current)
      Rails.logger.info("[Spirely] PcoInboundPeopleSyncJob complete for church #{church_id} — #{adults.size} adults, #{children.size} children")
    rescue Spirely::PcoError => e
      Rails.logger.error("[Spirely] PcoInboundPeopleSyncJob failed for church #{church_id}: #{e.message}")
      raise
    end

    private

    CLEARLY_MINOR_AGE = 18

    # PCO's own child/adult classification is sometimes just wrong —
    # confirmed on real jccag data (a child born 2020, actively checking
    # in via PCO Check-Ins, flagged "Adult" in PCO). This job only has
    # the People response, not check-in data, so — unlike
    # PcoAttendanceSyncJob#sync_person, which can trust birthdate the
    # instant it processes a check-in — an override here needs real,
    # already-synced local check-in evidence before trusting a
    # birthdate over PCO's own flag, to avoid guessing on stale/wrong
    # birthdate data for someone who's genuinely an inactive adult.
    def checked_in_pco_ids_for(church, people)
      Spirely::Person.joins(:attendances)
                      .where(church: church, pco_person_id: people.map { |p| p["id"] })
                      .distinct
                      .pluck(:pco_person_id).to_set
    end

    def treat_as_child?(person, checked_in_pco_ids)
      return true if person.dig("attributes", "child")
      return false unless checked_in_pco_ids.include?(person["id"])

      likely_a_minor?(person.dig("attributes", "birthdate"))
    end

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

    def tagged_household_ids(client, ministry_tag)
      all_tags = client.get_all("/people/v2/tags", "where[name]" => ministry_tag)
      tag = all_tags.find { |t| t.dig("attributes", "name") == ministry_tag }

      return Set.new unless tag

      tagged_people = client.get_all("/people/v2/tags/#{tag["id"]}/people")
      tagged_people.flat_map { |p|
        p.dig("relationships", "households", "data")&.map { |h| h["id"] } || []
      }.to_set
    end

    def sync_household(church, household_id, adults, households, emails, phones, addresses)
      family = find_family(church, household_id, adults)
      primary = primary_contact_for(family, households[household_id], adults)

      sync_family(church, family, primary, household_id, households[household_id], emails, phones, addresses)
      (adults - [primary]).each { |p| sync_guardian(family, p, emails, phones) }
    end

    # household_id first (the true grouping key, when there is one — a
    # solo adult with no PCO household relationship has none) — falls
    # back to matching any of these adults' own pco_person_id, which also
    # covers a family synced before pco_household_id was reliably
    # captured on it. Deliberately does not look up by a blank
    # household_id — that would match any other family that also
    # happens to have a null pco_household_id, not just this one.
    def find_family(church, household_id, adults)
      (household_id.present? && church.families.find_by(pco_household_id: household_id)) ||
        church.families.find_by(pco_person_id: adults.map { |p| p["id"] }) ||
        church.families.new
    end

    # Keeps using whoever's already the primary contact, for stability
    # across repeated syncs — otherwise which adult "wins" could flip
    # between runs depending on PCO's own response ordering. For a new
    # family, prefers PCO's own household primary_contact_id, if that
    # actually resolves to one of this batch's adults (household data can
    # point at a person who was miscategorized as a child at the time,
    # confirmed on real production data — falls through to the first
    # adult in that case).
    def primary_contact_for(family, household, adults)
      if family.persisted? && family.pco_person_id.present?
        existing = adults.find { |p| p["id"] == family.pco_person_id }
        return existing if existing
      end

      pco_primary_id = household&.dig("attributes", "primary_contact_id")
      adults.find { |p| p["id"] == pco_primary_id } || adults.first
    end

    def sync_family(church, family, person, household_id, household, emails, phones, addresses)
      pco_id  = person["id"]
      attrs   = person["attributes"]
      email   = primary_value(emails[pco_id], "address")
      phone   = primary_value(phones[pco_id], "number")
      address = format_address(primary_record(addresses[pco_id]))

      pco_attrs = {
        pco_person_id:      pco_id,
        pco_household_id:   household_id,
        pco_last_synced_at: Time.current,
        # Immutable on PCO's side once set — when this person was first
        # added to PCO, not when Spirely happened to sync them. The
        # actual "is this a new family" signal (see this column's own
        # migration comment for why local created_at can't be trusted).
        pco_created_at:     attrs["created_at"]&.then { |t| Time.zone.parse(t) }
      }

      profile_attrs = {
        family_name:                  household&.dig("attributes", "name") ||
                                      "#{attrs["last_name"]} Family",
        primary_contact_first_name:   attrs["first_name"].to_s.strip,
        primary_contact_last_name:    attrs["last_name"].to_s.strip,
        email:                        email,
        phone:                        phone,
        address:                      address
      }

      strategy = church.sync_setting.conflict_resolution

      if family.new_record? || strategy == "pco_wins"
        family.assign_attributes(pco_attrs.merge(profile_attrs))
      elsif strategy == "newest_wins"
        pco_updated = attrs["updated_at"]&.then { |t| Time.parse(t) }
        if pco_updated && pco_updated > (family.updated_at || Time.at(0))
          family.assign_attributes(pco_attrs.merge(profile_attrs))
        else
          family.assign_attributes(pco_attrs)
        end
      else
        family.assign_attributes(pco_attrs)
      end

      family.save! if family.changed?
    rescue => e
      Rails.logger.error("[Spirely] Failed to sync family pco_id=#{person["id"]} church=#{church.id}: #{e.message}")
    end

    # A second (or third...) adult in the household — not PCO's idea of
    # "relationship" (nothing reliable to map from), staff can fill that
    # in later same as a Quick-Add-entered guardian.
    def sync_guardian(family, person, emails, phones)
      return unless family.persisted?

      pco_id = person["id"]
      attrs  = person["attributes"]
      guardian = family.guardians.find_by(pco_person_id: pco_id) || family.guardians.build(pco_person_id: pco_id)

      guardian.assign_attributes(
        first_name: attrs["first_name"].to_s.strip.presence || "Unknown",
        last_name:  attrs["last_name"].to_s.strip,
        email:      primary_value(emails[pco_id], "address"),
        phone:      primary_value(phones[pco_id], "number")
      )
      guardian.save! if guardian.changed?
    rescue => e
      Rails.logger.error("[Spirely] Failed to sync guardian pco_id=#{person["id"]} family=#{family.id}: #{e.message}")
    end

    def sync_child(church, person, households)
      pco_id       = person["id"]
      attrs        = person["attributes"]
      household_id = person.dig("relationships", "households", "data", 0, "id")
      family       = church.families.find_by(pco_household_id: household_id)

      return unless family

      child = church.children.find_by(pco_person_id: pco_id) ||
              family.children.find_by(
                first_name: attrs["first_name"],
                last_name:  attrs["last_name"]
              ) ||
              family.children.build

      child.assign_attributes(
        first_name:         attrs["first_name"] || "Unknown",
        last_name:          attrs["last_name"]  || "Unknown",
        birthdate:          attrs["birthdate"],
        grade:              attrs["grade"],
        notes:              attrs["medical_notes"],
        pco_person_id:      pco_id,
        pco_last_synced_at: Time.current
      )

      child.save! if child.changed?
    rescue => e
      Rails.logger.error("[Spirely] Failed to sync child pco_id=#{person["id"]} church=#{church.id}: #{e.message}")
    end

    def index_by_id(included, type)
      included.select { |r| r["type"] == type }.index_by { |r| r["id"] }
    end

    def group_by_person(included, type)
      included
        .select { |r| r["type"] == type }
        .group_by { |r| r.dig("relationships", "person", "data", "id") }
    end

    def primary_value(records, field)
      return nil if records.nil?
      primary = records.find { |r| r.dig("attributes", "primary") }
      (primary || records.first)&.dig("attributes", field)
    end

    def primary_record(records)
      return nil if records.nil?
      records.find { |r| r.dig("attributes", "primary") } || records.first
    end

    def format_address(record)
      return nil unless record
      a = record["attributes"] || {}
      parts = [
        a["street"],
        a["city"],
        [a["state"], a["zip"]].compact.join(" ")
      ].map(&:presence).compact
      parts.join(", ").presence
    end
  end
end
