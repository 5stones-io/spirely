module Spirely
  class PcoOutboundProfileSyncJob < ApplicationJob
    def perform(family_id)
      family = Family.find(family_id)
      church = family.church

      return unless family.pco_sync_enabled?
      return unless church.sync_setting&.outbound_people_sync?
      return if family.pco_person_id.blank?
      return unless church.church_integration&.pco_connected?

      client = Spirely::PcoClient.new(church.church_integration)

      client.patch("/people/v2/people/#{family.pco_person_id}", {
        data: {
          type:       "Person",
          id:         family.pco_person_id,
          attributes: pco_attributes(family)
        }
      })

      family.update_column(:pco_last_synced_at, Time.current)
      Rails.logger.info("[Spirely] PcoOutboundProfileSyncJob complete for family #{family_id} (church #{church.id})")
    rescue ActiveRecord::RecordNotFound
      Rails.logger.warn("[Spirely] PcoOutboundProfileSyncJob: family #{family_id} not found, discarding")
    rescue Spirely::PcoError => e
      Rails.logger.error("[Spirely] PcoOutboundProfileSyncJob failed for family #{family_id}: #{e.message}")
      raise
    end

    private

    def pco_attributes(family)
      {
        first_name: family.primary_contact_first_name,
        last_name:  family.primary_contact_last_name,
        contact_data: {
          email_addresses: [
            { address: family.email, primary: true }
          ].compact,
          phone_numbers: [
            family.phone.present? ? { number: family.phone, primary: true } : nil
          ].compact
        }
      }.compact
    end
  end
end
