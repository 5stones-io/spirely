module Spirely
  module Api
    module V1
      class SyncSettingsController < BaseController
        before_action :require_admin!

        def show
          render json: SyncSettingBlueprint.render(SyncSetting.current)
        end

        def update
          settings = SyncSetting.current
          was_auto  = settings.auto_sync_enabled?

          if settings.update(sync_setting_params)
            # If auto-sync was just enabled, kick off the scheduled chain
            if settings.auto_sync_enabled? && !was_auto
              Spirely::PcoScheduledSyncJob.kick_off_if_enabled!
            end
            render json: SyncSettingBlueprint.render(settings)
          else
            render json: { error: settings.errors.full_messages.first, code: "validation_error" },
                   status: :unprocessable_entity
          end
        end

        private

        def sync_setting_params
          params.require(:sync_setting).permit(
            :inbound_people_sync,
            :outbound_people_sync,
            :sync_frequency_hours,
            :conflict_resolution,
            :auto_sync_enabled,
            :pco_ministry_tag
          )
        end
      end
    end
  end
end
