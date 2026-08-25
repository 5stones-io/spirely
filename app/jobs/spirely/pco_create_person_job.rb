module Spirely
  # Creates a brand-new person (and their children) in Planning Center when a
  # family is quick-added and doesn't already have a PCO ID.
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

      if family.email.present?
        client.post("/people/v2/people/#{pco_person_id}/emails", {
          data: { type: "Email", attributes: { address: family.email, primary: true, location: "Home" } }
        })
      end

      if family.phone.present?
        client.post("/people/v2/people/#{pco_person_id}/phone_numbers", {
          data: { type: "PhoneNumber", attributes: { number: family.phone, primary: true, location: "Mobile" } }
        })
      end

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

      # PCO has no direct "parent" attribute on Person — a household is what
      # actually links a parent and their kids. Household creation only
      # sets the primary_contact as a member; each child needs its own
      # membership call after, added as child_or_dependent — confirmed
      # directly against a real PCO org while debugging this job, there's
      # no single call that does both.
      if child_pco_ids.any?
        household_id = family.pco_household_id
        if household_id.blank?
          household_resp = client.post("/people/v2/households", {
            data: {
              type: "Household",
              attributes: { name: family.family_name, primary_contact_id: pco_person_id }
            }
          })
          household_id = household_resp.dig("data", "id")
          family.update_column(:pco_household_id, household_id) if household_id
        end

        # Not guarded per-child the way person creation is above — there's
        # no cheap way to know which children already have a confirmed
        # membership without an extra GET. Re-adding an already-linked
        # child on a retry is a much smaller risk than leaving one
        # permanently unlinked because an earlier attempt's household
        # call succeeded but a later child's membership call didn't.
        if household_id
          child_pco_ids.each do |child_id|
            client.post("/people/v2/households/#{household_id}/household_memberships", {
              data: {
                type: "HouseholdMembership",
                attributes: { person_id: child_id, household_role: "child_or_dependent" }
              }
            })
          end
        end
      end

      family.update_column(:pco_last_synced_at, Time.current)

      Rails.logger.info("[Spirely] PcoCreatePersonJob: synced family #{family_id} (church #{church.id}), pco_person_id=#{pco_person_id}")
    rescue ActiveRecord::RecordNotFound
      Rails.logger.warn("[Spirely] PcoCreatePersonJob: family #{family_id} not found")
    rescue Spirely::PcoError => e
      Rails.logger.error("[Spirely] PcoCreatePersonJob failed for family #{family_id}: #{e.message}")
      raise
    end
  end
end
