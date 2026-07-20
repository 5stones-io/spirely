module Spirely
  class PcoScheduledSyncJob < ApplicationJob
    queue_as :default

    def perform
      settings = SyncSetting.current
      return unless settings.auto_sync_enabled?

      Rails.logger.info("[Spirely] PcoScheduledSyncJob: running automatic sync")

      PcoInboundPeopleSyncJob.perform_now if settings.inbound_people_sync?

      reschedule(settings.sync_frequency_hours)
    rescue => e
      Rails.logger.error("[Spirely] PcoScheduledSyncJob error: #{e.message}")
      reschedule(settings&.sync_frequency_hours || 6)
      raise
    end

    def self.kick_off_if_enabled!
      settings = SyncSetting.current
      return unless settings.auto_sync_enabled?

      set(wait: settings.sync_frequency_hours.hours).perform_later
      Rails.logger.info("[Spirely] Auto-sync scheduled every #{settings.sync_frequency_hours}h")
    rescue => e
      Rails.logger.warn("[Spirely] Could not schedule auto-sync: #{e.message}")
    end

    private

    def reschedule(hours)
      self.class.set(wait: hours.to_i.hours).perform_later
    end
  end
end
