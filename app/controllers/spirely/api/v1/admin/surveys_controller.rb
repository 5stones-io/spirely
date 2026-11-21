module Spirely
  module Api
    module V1
      module Admin
        # Survey results for admins and owners (5ST-84): how many answered,
        # counts for each choice and every written answer. Answers are
        # anonymous, so there's nothing here about who sent them.
        class SurveysController < BaseController
          before_action { require_feature!("surveys") }
          before_action :require_admin!
          before_action :set_survey, only: %i[show update]

          # GET /api/v1/admin/surveys
          def index
            surveys = Current.church.surveys.order(created_at: :desc, id: :desc)
            counts = Spirely::SurveyResponse.where(survey_id: surveys.select(:id)).group(:survey_id).count
            render json: { surveys: surveys.map { |s| survey_json(s, counts.fetch(s.id, 0)) } }
          end

          # GET /api/v1/admin/surveys/:id
          def show
            render json: {
              survey: survey_json(@survey, @survey.responses.count).merge(intro: @survey.intro),
              results: results_json,
            }
          end

          # PATCH /api/v1/admin/surveys/:id  { survey: { status, show_on_home } }
          def update
            @survey.update!(params.require(:survey).permit(:status, :show_on_home))
            render json: { survey: survey_json(@survey, @survey.responses.count) }
          rescue ActiveRecord::RecordInvalid => e
            render json: { error: e.message, code: "validation_error" }, status: :unprocessable_entity
          end

          private

          def set_survey
            @survey = Current.church.surveys.find_by(id: params[:id])
            render json: { error: "Not found", code: "not_found" }, status: :not_found unless @survey
          end

          def survey_json(survey, response_count)
            { id: survey.id, slug: survey.slug, title: survey.title, status: survey.status,
              show_on_home: survey.show_on_home, response_count: response_count,
              opened_at: survey.opened_at, closed_at: survey.closed_at }
          end

          # Each question with its results, in the survey's order.
          def results_json
            results = @survey.results.index_by { |r| r[:id] }
            @survey.questions.map do |q|
              q.slice("id", "type", "text", "section", "max", "follow_up").merge(results.fetch(q["id"]))
            end
          end
        end
      end
    end
  end
end
