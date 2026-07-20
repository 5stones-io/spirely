module Spirely
  module Api
    module V1
      class FamiliesController < BaseController
        before_action :require_family!

        def show
          render json: FamilyBlueprint.render(current_family, view: :with_children)
        end

        def update
          if current_family.update(family_params)
            render json: FamilyBlueprint.render(current_family, view: :with_children)
          else
            render json: { error: current_family.errors.full_messages.first, code: "validation_error" },
                   status: :unprocessable_entity
          end
        end

        private

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
