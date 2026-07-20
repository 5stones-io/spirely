module Spirely
  module Api
    module V1
      class ChildrenController < BaseController
        before_action :require_family!
        before_action :set_child, only: [:update, :destroy]

        def index
          render json: ChildBlueprint.render(current_family.children.order(:first_name, :last_name))
        end

        def create
          child = current_family.children.build(child_params)
          if child.save
            render json: ChildBlueprint.render(child), status: :created
          else
            render json: { error: child.errors.full_messages.first, code: "validation_error" },
                   status: :unprocessable_entity
          end
        end

        def update
          if @child.update(child_params)
            render json: ChildBlueprint.render(@child)
          else
            render json: { error: @child.errors.full_messages.first, code: "validation_error" },
                   status: :unprocessable_entity
          end
        end

        def destroy
          @child.destroy
          head :no_content
        end

        private

        def set_child
          @child = current_family.children.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Child not found", code: "not_found" }, status: :not_found
        end

        def child_params
          params.require(:child).permit(:first_name, :last_name, :birthdate, :grade, :notes)
        end
      end
    end
  end
end
