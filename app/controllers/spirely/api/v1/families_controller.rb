module Spirely
  module Api
    module V1
      class FamiliesController < BaseController
        before_action :require_family!

        def show
          render json: family_json
        end

        def update
          if current_family.update(family_params)
            render json: family_json
          else
            render json: { error: current_family.errors.full_messages.first, code: "validation_error" },
                   status: :unprocessable_entity
          end
        end

        private

        # Multi-account family access means the signed-in account isn't
        # always the family's own primary contact — real bug this fixes:
        # ParentHome.tsx's "Hi, {name}" greeted every signed-in guardian
        # with the *family's* primary contact name (e.g. "Hi, Matt" shown
        # to Danielle, signed in on her own account). viewer_first_name
        # is the actual signed-in person's own name, same current_guardian
        # resolution the volunteer-detection fix uses.
        def family_json
          FamilyBlueprint.render_as_hash(current_family, view: :with_children)
                          .merge(viewer_first_name: current_guardian&.first_name || current_family.primary_contact_first_name)
        end

        def family_params
          params.require(:family).permit(
            :family_name,
            :primary_contact_first_name, :primary_contact_last_name,
            :email, :phone, :address
          )
        end
      end
    end
  end
end
