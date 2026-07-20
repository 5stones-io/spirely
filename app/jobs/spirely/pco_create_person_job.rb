module Spirely
  # Creates a brand-new person (and their children) in Planning Center when a
  # family is quick-added in spirely and doesn't already have a PCO ID.
  class PcoCreatePersonJob < ApplicationJob
    def perform(family_id)
      family = Family.find(family_id)

      return if family.pco_person_id.present?          # already in PCO
      return unless family.pco_sync_enabled?
      return unless ChurchIntegration.current.access_token.present?

      client = PcoClient.new

      # ── 1. Create the primary contact in PCO ────────────────────────────
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

      # ── 2. Add email ─────────────────────────────────────────────────────
      if family.email.present?
        client.post("/people/v2/people/#{pco_person_id}/emails", {
          data: { type: "Email", attributes: { address: family.email, primary: true } }
        })
      end

      # ── 3. Add phone ─────────────────────────────────────────────────────
      if family.phone.present?
        client.post("/people/v2/people/#{pco_person_id}/phone_numbers", {
          data: { type: "PhoneNumber", attributes: { number: family.phone, primary: true, location: "Mobile" } }
        })
      end

      # ── 4. Apply ministry tag ─────────────────────────────────────────────
      tag_name = SyncSetting.current.effective_ministry_tag
      if tag_name.present?
        all_tags = client.get_all("/people/v2/tags", "where[name]" => tag_name)
        tag = all_tags.find { |t| t.dig("attributes", "name") == tag_name }
        if tag
          client.post("/people/v2/tags/#{tag["id"]}/relationships/people", {
            "data" => [{ "type" => "Person", "id" => pco_person_id }]
          })
        end
      end

      # ── 5. Create children ───────────────────────────────────────────────
      family.children.each do |child|
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
        child.update_column(:pco_person_id, child_pco_id) if child_pco_id
      end

      # ── 6. Store PCO IDs on the family ───────────────────────────────────
      family.update_columns(
        pco_person_id:      pco_person_id,
        pco_last_synced_at: Time.current
      )

      Rails.logger.info("[Spirely] PcoCreatePersonJob: created PCO person #{pco_person_id} for family #{family_id}")

    rescue ActiveRecord::RecordNotFound
      Rails.logger.warn("[Spirely] PcoCreatePersonJob: family #{family_id} not found")
    rescue PcoError => e
      Rails.logger.error("[Spirely] PcoCreatePersonJob failed for family #{family_id}: #{e.message}")
      raise
    end
  end
end
