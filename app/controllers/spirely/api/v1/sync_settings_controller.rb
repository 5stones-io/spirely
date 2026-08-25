module Spirely
  module Api
    module V1
      class SyncSettingsController < BaseController
        before_action :require_admin!

        def show
          render json: SyncSettingBlueprint.render(current_sync_setting)
        end

        def update
          settings = current_sync_setting
          if settings.update(sync_setting_params)
            render json: SyncSettingBlueprint.render(settings)
          else
            render json: { error: settings.errors.full_messages.first, code: "validation_error" },
                   status: :unprocessable_entity
          end
        end

        private

        def current_sync_setting
          Current.church.sync_setting || Current.church.create_sync_setting!
        end

        def sync_setting_params
          params.require(:sync_setting).permit(
            :inbound_people_sync,
            :outbound_people_sync,
            :sync_frequency_hours,
            :conflict_resolution,
            :auto_sync_enabled,
            :pco_ministry_tag,
            :pco_assessment_field_id,
            :pco_assessment_field_name,
            pco_kids_service_types: [:service_type_id, :service_type_name, :check_ins_event_name],
            pco_event_tags: [:tag_id, :tag_name]
          )
        end
      end
    end
  end
end
