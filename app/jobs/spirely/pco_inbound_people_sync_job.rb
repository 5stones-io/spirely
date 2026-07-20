module Spirely
  class PcoInboundPeopleSyncJob < ApplicationJob
    def perform
      return unless SyncSetting.current.inbound_people_sync?

      client = PcoClient.new

      # If a ministry tag is configured, limit the sync to households that
      # contain at least one person bearing that tag (the primary contact).
      tagged_hh_ids = tagged_household_ids(client) if ministry_tag.present?

      if tagged_hh_ids&.empty?
        Rails.logger.warn("[Spirely] PcoInboundPeopleSyncJob: tag '#{ministry_tag}' matched no people — sync aborted")
        return
      end

      response = client.paginate(
        "/people/v2/people",
        include: "households,emails,phone_numbers,addresses"
      )

      people    = response["data"]
      included  = response["included"]

      # Restrict to tagged households when the tag is configured
      if tagged_hh_ids
        people = people.select { |p|
          hh_id = p.dig("relationships", "households", "data", 0, "id")
          tagged_hh_ids.include?(hh_id)
        }
        Rails.logger.info("[Spirely] Tag filter active — #{people.size} people in #{tagged_hh_ids.size} tagged households")
      end

      households = index_by_id(included, "Household")
      emails     = group_by_person(included, "Email")
      phones     = group_by_person(included, "PhoneNumber")
      addresses  = group_by_person(included, "Address")

      adults   = people.reject { |p| p.dig("attributes", "child") }
      children = people.select { |p| p.dig("attributes", "child") }

      adults.each   { |p| sync_family(p, households, emails, phones, addresses) }
      children.each { |p| sync_child(p, households) }

      SyncSetting.current.update!(last_synced_at: Time.current)
      Rails.logger.info("[Spirely] PcoInboundPeopleSyncJob complete — #{adults.size} adults, #{children.size} children")
    rescue PcoError => e
      Rails.logger.error("[Spirely] PcoInboundPeopleSyncJob failed: #{e.message}")
      raise
    end

    private

    # Returns a Set of PCO household IDs that contain at least one person
    # tagged with the ministry tag, or nil if no tag is configured.
    def tagged_household_ids(client)
      # Find the tag by name
      all_tags = client.get_all("/people/v2/tags", "where[name]" => ministry_tag)
      tag = all_tags.find { |t| t.dig("attributes", "name") == ministry_tag }

      unless tag
        Rails.logger.warn("[Spirely] PCO tag '#{ministry_tag}' not found — check PCO_MINISTRY_TAG")
        return Set.new
      end

      # Fetch every person bearing that tag and collect their household IDs
      tagged_people = client.get_all("/people/v2/tags/#{tag["id"]}/people")
      ids = tagged_people.flat_map { |p|
        p.dig("relationships", "households", "data")&.map { |h| h["id"] } || []
      }.to_set

      Rails.logger.info("[Spirely] PCO tag '#{ministry_tag}' (id=#{tag["id"]}) → #{ids.size} households")
      ids
    end

    def ministry_tag
      SyncSetting.current.effective_ministry_tag
    end

    def sync_family(person, households, emails, phones, addresses)
      pco_id       = person["id"]
      attrs        = person["attributes"]
      household_id = person.dig("relationships", "households", "data", 0, "id")
      household    = households[household_id]
      email        = primary_value(emails[pco_id], "address")
      phone        = primary_value(phones[pco_id], "number")
      address      = format_address(primary_record(addresses[pco_id]))

      family = Family.find_by(pco_person_id: pco_id) ||
               (email.present? && Family.find_by(email: email)) ||
               Family.new

      pco_attrs = {
        pco_person_id:      pco_id,
        pco_household_id:   household_id,
        pco_last_synced_at: Time.current
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

      strategy = SyncSetting.current.conflict_resolution

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
      Rails.logger.error("[Spirely] Failed to sync family pco_id=#{person["id"]}: #{e.message}")
    end

    def sync_child(person, households)
      pco_id       = person["id"]
      attrs        = person["attributes"]
      household_id = person.dig("relationships", "households", "data", 0, "id")
      family       = Family.find_by(pco_household_id: household_id)

      return unless family

      child = Child.find_by(pco_person_id: pco_id) ||
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
      Rails.logger.error("[Spirely] Failed to sync child pco_id=#{person["id"]}: #{e.message}")
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
