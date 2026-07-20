module Spirely
  class SyncSettingBlueprint < ::Blueprinter::Base
    identifier :id

    fields :inbound_people_sync, :outbound_people_sync,
           :sync_frequency_hours, :conflict_resolution,
           :auto_sync_enabled, :pco_ministry_tag,
           :last_synced_at, :updated_at
  end
end
