module Spirely
  module Api
    module V1
      module Admin
        # Settings → Time card categories: the codes hours and tasks count
        # toward. Turned off rather than deleted, so past hours keep theirs.
        class TimeCategoriesController < BaseController
          include Spirely::TimeCardJson

          before_action :require_admin!

          # GET /api/v1/admin/time_categories
          def index
            render json: { categories: Current.church.time_categories.ordered.map { |c| time_category_json(c) } }
          end

          # POST /api/v1/admin/time_categories  { code, name }
          def create
            category = Current.church.time_categories.create!(params.permit(:code, :name))
            render json: time_category_json(category), status: :created
          end

          # PATCH /api/v1/admin/time_categories/:id  { code?, name?, active? }
          def update
            category = Current.church.time_categories.find(params[:id])
            category.assign_attributes(params.permit(:code, :name))
            if params.key?(:active)
              category.archived_at = ActiveModel::Type::Boolean.new.cast(params[:active]) ? nil : (category.archived_at || Time.current)
            end
            category.save!
            render json: time_category_json(category)
          end

          rescue_from ActiveRecord::RecordInvalid do |e|
            render json: { error: e.record.errors.full_messages.to_sentence, code: "validation_error" }, status: :unprocessable_entity
          end
        end
      end
    end
  end
end
