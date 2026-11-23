module Spirely
  # Creates a brand-new person, any other parent and their children in
  # Planning Center, in one household, when a family is quick-added or a
  # sign-up approved and doesn't already have a PCO ID.
  class PcoCreatePersonJob < ApplicationJob
    def perform(family_id)
      family = Family.find(family_id)
      church = family.church

      # pco_last_synced_at, not pco_person_id — it's only ever set once the
      # *whole* sync (person, email/phone/tag, children, household) has
      # completed, whereas pco_person_id can legitimately be present mid-way
      # through a retry (see below). Guarding on pco_person_id here would
      # incorrectly skip retrying a family stuck partway through.
      return if family.pco_last_synced_at.present?
      return unless family.pco_sync_enabled?
      return unless church.church_integration&.pco_connected?

      client = Spirely::PcoClient.new(church.church_integration)

      pco_person_id = family.pco_person_id
      retrying = pco_person_id.present?
      if pco_person_id.blank?
        person_resp = client.post("/people/v2/people", {
          data: {
            type: "Person",
            attributes: {
              first_name: family.primary_contact_first_name,
              last_name:  family.primary_contact_last_name,
            }
          }
        })
        pco_person_id = person_resp.dig("data", "id")
        raise "PCO did not return a person id" unless pco_person_id
        pco_created_at = person_resp.dig("data", "attributes", "created_at")&.then { |t| Time.zone.parse(t) }

        # Persisted immediately, not just as part of pco_last_synced_at at
        # the very end — a retry after a later step fails (email/phone/tag/
        # children/household) must reuse this same PCO person, not create
        # another one from scratch. This is exactly what produced 10
        # duplicate "Brad Singletary" records in jccag's real PCO org on
        # 2026-08-07: every retry re-ran the whole thing because nothing
        # was saved until 100% success. pco_created_at is what the
        # New-Family Nudge actually keys off now (see that column's own
        # migration comment) — set here immediately too, not just via
        # inbound sync, so a Quick-Add family shows up as "new" right away.
        family.update_columns(pco_person_id: pco_person_id, pco_created_at: pco_created_at)
      end

      # On a retry the person may already have these: PCO refuses a
      # duplicate (409), which stopped every retry for the Kamaras
      # (2026-11-22) before it got to their household.
      add_contact(client, pco_person_id, email: family.email, phone: family.phone, check: retrying)

      Spirely::PcoAddress.push(client, pco_person_id, family.address)

      tag_name = church.sync_setting&.effective_ministry_tag
      if tag_name.present?
        all_tags = client.get_all("/people/v2/tags", "where[name]" => tag_name)
        tag = all_tags.find { |t| t.dig("attributes", "name") == tag_name }
        if tag
          client.post("/people/v2/tags/#{tag["id"]}/relationships/people", {
            "data" => [{ "type" => "Person", "id" => pco_person_id }]
          })
        end
      end

      # Another parent added on Quick Add. Saved one at a time, like the
      # primary contact, so a retry doesn't make them twice.
      guardian_pco_ids = family.guardians.order(:id).map do |g|
        next g.pco_person_id if g.pco_person_id.present?

        resp = client.post("/people/v2/people", {
          data: { type: "Person", attributes: { first_name: g.first_name, last_name: g.last_name.presence || family.primary_contact_last_name } }
        })
        id = resp.dig("data", "id")
        raise "PCO did not return a person id" unless id

        g.update_column(:pco_person_id, id)
        add_contact(client, id, email: g.email, phone: g.phone, check: false)
        id
      end

      child_pco_ids = []
      family.children.each do |child|
        if child.pco_person_id.present?
          child_pco_ids << child.pco_person_id
          next
        end

        child_resp = client.post("/people/v2/people", {
          data: {
            type: "Person",
            attributes: {
              first_name: child.first_name,
              last_name:  child.last_name,
              child:      true,
              grade:      child.grade,
              birthdate:  child.birthdate&.iso8601,
              medical_notes: child.notes,
            }.compact
          }
        })
        child_pco_id = child_resp.dig("data", "id")
        next unless child_pco_id

        child.update_column(:pco_person_id, child_pco_id)
        child_pco_ids << child_pco_id
      end

      # A household is what links a parent and their kids in PCO. One call
      # makes it with everyone in it; members and the primary contact go in
      # relationships (PCO's format, planningcenter/developers#463). Named
      # the way PCO names households, "Rivera Household".
      others = guardian_pco_ids + child_pco_ids
      if others.any? && family.pco_household_id.blank?
        person = ->(id) { { type: "Person", id: id } }
        household_resp = client.post("/people/v2/households", {
          data: {
            type: "Household",
            attributes: { name: "#{family.primary_contact_last_name.presence || family.family_name} Household" },
            relationships: {
              people: { data: [pco_person_id, *others].map(&person) },
              primary_contact: { data: person.(pco_person_id) },
            },
          }
        })
        household_id = household_resp.dig("data", "id")
        family.update_column(:pco_household_id, household_id) if household_id
      end

      family.update_column(:pco_last_synced_at, Time.current)

      Rails.logger.info("[Spirely] PcoCreatePersonJob: synced family #{family_id} (church #{church.id}), pco_person_id=#{pco_person_id}")
    rescue ActiveRecord::RecordNotFound
      Rails.logger.warn("[Spirely] PcoCreatePersonJob: family #{family_id} not found")
    rescue Spirely::PcoError => e
      detail = e.respond_to?(:body) && e.body.present? ? " #{e.body.to_s.truncate(500)}" : ""
      Rails.logger.error("[Spirely] PcoCreatePersonJob failed for family #{family_id}: #{e.message}#{detail}")
      raise
    end

    private

    # The email and phone on a PCO person, skipping any it already has
    # when check is true.
    def add_contact(client, person_id, email:, phone:, check:)
      if email.present? && !(check && has?(client, person_id, "emails", "address") { _1.to_s.casecmp?(email) })
        client.post("/people/v2/people/#{person_id}/emails", {
          data: { type: "Email", attributes: { address: email, primary: true, location: "Home" } }
        })
      end

      digits = ->(n) { n.to_s.gsub(/\D/, "").last(10) }
      if phone.present? && !(check && has?(client, person_id, "phone_numbers", "number") { digits.(_1) == digits.(phone) })
        client.post("/people/v2/people/#{person_id}/phone_numbers", {
          data: { type: "PhoneNumber", attributes: { number: phone, primary: true, location: "Mobile" } }
        })
      end
    end

    def has?(client, person_id, kind, attribute, &match)
      Array(client.get("/people/v2/people/#{person_id}/#{kind}")["data"]).any? { match.(_1.dig("attributes", attribute)) }
    end
  end
end
