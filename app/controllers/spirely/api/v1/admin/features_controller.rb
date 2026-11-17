module Spirely
  module Api
    module V1
      module Admin
        # Settings → Features (5ST-81): turn the church's core features
        # (Church::FEATURES) off and back on. Turning one off hides it from
        # everyone and stops its background work; nothing is deleted.
        class FeaturesController < BaseController
          before_action :require_admin!

          # GET /api/v1/admin/features
          def show
            render json: features_json
          end

          # PATCH /api/v1/admin/features  { disabled_features: [...] }
          # The whole list of what's off; an empty list turns everything on.
          def update
            disabled = Array(params[:disabled_features]).map(&:to_s).compact_blank.uniq
            if Current.church.update(disabled_features: disabled)
              render json: features_json
            else
              render json: { error: Current.church.errors.full_messages.first, code: "validation_error" },
                     status: :unprocessable_entity
            end
          end

          private

          def features_json
            church = Current.church
            {
              features: Church::FEATURES.map do |id, feature|
                {
                  id: id,
                  label: feature[:label],
                  description: feature[:description],
                  # Only listed in Settings while this ministry module is on.
                  module: feature[:module],
                  # Can't be on without this one (prayer needs family posts).
                  requires: feature[:requires],
                  # This feature's own switch…
                  enabled: !church.disabled_features.include?(id),
                }
              end,
              # …and what's actually on, after `requires`.
              enabled_features: church.enabled_features,
            }
          end
        end
      end
    end
  end
end
