module Spirely
  module Api
    module V1
      class SyncController < BaseController
        before_action :require_admin!

        def trigger
          settings = SyncSetting.current
          enqueued = []

          if settings.inbound_people_sync?
            Spirely::PcoInboundPeopleSyncJob.perform_later
            enqueued << "inbound_people"
          end

          if settings.outbound_people_sync?
            Spirely::Family.where(pco_sync_enabled: true).find_each do |family|
              Spirely::PcoOutboundProfileSyncJob.perform_later(family.id)
            end
            enqueued << "outbound_people"
          end

          render json: { status: "started", enqueued: enqueued, timestamp: Time.current.iso8601 }
        end
      end
    end
  end
end
