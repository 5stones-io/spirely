module Spirely
  module Api
    module V1
      class SyncController < BaseController
        before_action :require_admin!

        # scope=attendance (e.g. Checked In Now's own "Sync check-ins"
        # button) enqueues only the attendance pull, skipping inbound/
        # outbound people sync entirely regardless of SyncSetting flags —
        # a full sync isn't what a staff member watching live check-ins
        # mid-service wants to wait behind. Omitted (Settings' own "Sync
        # Now" button), behavior is unchanged from before this existed.
        def trigger
          settings = Current.church.sync_setting
          attendance_only = params[:scope] == "attendance"
          enqueued = []

          if !attendance_only && settings&.inbound_people_sync?
            Spirely::PcoInboundPeopleSyncJob.perform_later(Current.church.id)
            enqueued << "inbound_people"
          end

          if !attendance_only && settings&.outbound_people_sync?
            Current.church.families.where(pco_sync_enabled: true).find_each do |family|
              Spirely::PcoOutboundProfileSyncJob.perform_later(family.id)
            end
            enqueued << "outbound_people"
          end

          # Unconditional (no SyncSetting flag) - unlike outbound profile
          # sync, this isn't an opt-in extra; it's core CRM data the
          # Attendance Nudge depends on. Only gated on PCO being connected
          # at all, same as the other two.
          if Current.church.church_integration&.pco_connected?
            Spirely::PcoAttendanceSyncJob.perform_later(Current.church.id)
            enqueued << "attendance"
          end

          render json: { status: "started", enqueued: enqueued, timestamp: Time.current.iso8601 }
        end
      end
    end
  end
end
