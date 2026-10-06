module Spirely
  # Pulls PCO Check-Ins' own all-time per-person stats
  # (Person#last_checked_in_at / #check_in_count) onto Spirely::Person —
  # the real fix for the Families list's "Never checked in", which used
  # to be computed from local Attendance alone and so only ever saw
  # PcoAttendanceSyncJob's rolling 16-week window. PcoAttendanceSyncJob
  # already stores these same two fields for anyone in that window; this
  # covers everyone else.
  #
  # Ordered by -check_in_count and stops at the first person who has
  # never checked in, so it only pages through people with real history
  # rather than every Check-Ins person PCO has (all of People, mirrored).
  #
  # Creates a Person row only for a PCO id this church already knows as
  # a child, family primary contact or guardian — the only people the
  # Families list ever looks up — rather than for every attendee in PCO's
  # history; an existing Person (volunteer etc.) just gets its stats
  # refreshed. Email is deliberately never set here, so the
  # `people.find_by(email:)` fallbacks elsewhere can't start resolving
  # to one of these rows.
  class PcoCheckInStatsSyncJob < ApplicationJob
    PATH = "/check-ins/v2/people".freeze
    RATE_LIMIT_PAUSE = 20 # seconds — PCO's limit is 100 requests / 20s

    def perform(church_id)
      church = Church.find(church_id)
      return unless church.church_integration&.pco_connected?

      client    = Spirely::PcoClient.new(church.church_integration)
      known_ids = known_pco_person_ids(church)
      offset    = 0
      synced    = 0

      loop do
        page = fetch_page(client, offset)
        people = Array(page["data"])

        people.each do |pco_person|
          return finish(church_id, synced) if pco_person.dig("attributes", "check_in_count").to_i.zero?

          synced += 1 if sync_person(church, pco_person, known_ids)
        end

        break if people.size < Spirely::PcoClient::PAGE_SIZE || page.dig("links", "next").blank?

        offset += Spirely::PcoClient::PAGE_SIZE
      end

      finish(church_id, synced)
    rescue Spirely::PcoError => e
      Rails.logger.error("[Spirely] PcoCheckInStatsSyncJob failed for church #{church_id}: #{e.message}")
      raise
    end

    private

    def fetch_page(client, offset, retried: false)
      client.get(PATH, order: "-check_in_count", per_page: Spirely::PcoClient::PAGE_SIZE, offset: offset)
    rescue Spirely::PcoApiError => e
      raise unless e.status == 429 && !retried

      sleep RATE_LIMIT_PAUSE
      fetch_page(client, offset, retried: true)
    end

    def known_pco_person_ids(church)
      family_ids = church.families.select(:id)
      Set.new(church.families.where.not(pco_person_id: nil).pluck(:pco_person_id)) |
        church.children.where.not(pco_person_id: nil).pluck(:pco_person_id) |
        Spirely::Guardian.where(family_id: family_ids).where.not(pco_person_id: nil).pluck(:pco_person_id)
    end

    def sync_person(church, pco_person, known_ids)
      pco_id = pco_person["id"]
      attrs  = pco_person["attributes"]

      person = church.people.find_by(pco_person_id: pco_id)
      return false unless person || known_ids.include?(pco_id)

      person ||= church.people.new(
        pco_person_id: pco_id,
        first_name:    attrs["first_name"].presence || "Unknown",
        last_name:     attrs["last_name"],
        child:         attrs["child"] || false,
        birthdate:     attrs["birthdate"]
      )
      person.assign_attributes(
        last_checked_in_at: attrs["last_checked_in_at"],
        check_in_count:     attrs["check_in_count"]
      )
      return false unless person.new_record? || person.changed?

      person.save!
      true
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("[Spirely] PcoCheckInStatsSyncJob: skipped pco_id=#{pco_id} church=#{church.id}: #{e.message}")
      false
    end

    def finish(church_id, synced)
      Rails.logger.info("[Spirely] PcoCheckInStatsSyncJob complete for church #{church_id} — #{synced} people updated")
    end
  end
end
