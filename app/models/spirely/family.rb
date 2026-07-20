module Spirely
  class Family < ApplicationRecord
    belongs_to :account, optional: true
    has_many :children,  dependent: :destroy
    has_many :guardians, dependent: :destroy

    validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

    after_commit :enqueue_outbound_profile_sync, on: :update, if: :profile_changed?

    def primary_contact_name
      "#{primary_contact_first_name} #{primary_contact_last_name}".strip
    end

    def primary_contact_name=(full_name)
      parts = full_name.to_s.strip.split(" ", 2)
      self.primary_contact_first_name = parts[0].to_s
      self.primary_contact_last_name  = parts[1].to_s
    end

    private

    def profile_changed?
      previous_changes.keys.intersect?(%w[
        family_name primary_contact_first_name primary_contact_last_name email phone
      ])
    end

    def enqueue_outbound_profile_sync
      return unless pco_sync_enabled?
      return unless SyncSetting.current.outbound_people_sync?

      Spirely::PcoOutboundProfileSyncJob.perform_later(id)
    end
  end
end
