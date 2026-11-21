module Spirely
  module Api
    module V1
      # Anonymous surveys on the church's site (5ST-84). No sign-in, and
      # nothing about who answered is saved, even for someone signed in.
      class SurveysController < BaseController
        skip_before_action :authenticate!
        before_action { require_feature!("surveys") }
        before_action :set_survey, only: %i[show respond]

        # GET /api/v1/surveys — open surveys for the home page's card.
        def index
          surveys = Current.church.surveys.taking_answers.where(show_on_home: true).order(opened_at: :desc, id: :desc)
          render json: { surveys: surveys.map { |s| { slug: s.slug, title: s.title, blurb: s.home_blurb } } }
        end

        # GET /api/v1/surveys/:slug
        def show
          render json: {
            slug: @survey.slug, title: @survey.title, intro: @survey.intro, thanks: @survey.thanks,
            church_name: Current.church.name, open: @survey.open?,
            questions: @survey.open? ? @survey.questions : [],
          }
        end

        # POST /api/v1/surveys/:slug/responses  { answers: { id => { value, other, follow_up } } }
        #
        # `website` is a field the page hides from people; a bot that fills
        # it in gets the usual answer and nothing is saved.
        def respond
          unless @survey.open?
            return render json: { error: "This survey is closed.", code: "closed" }, status: :unprocessable_entity
          end
          return head :created if params[:website].present?

          answers = @survey.clean_answers(params[:answers])
          if answers.empty?
            return render json: { error: "Answer at least one question.", code: "no_answers" }, status: :unprocessable_entity
          end

          @survey.responses.create!(answers: answers)
          head :created
        end

        private

        def set_survey
          @survey = Current.church.surveys.find_by(slug: params[:slug])
          render json: { error: "We couldn't find that survey.", code: "not_found" }, status: :not_found unless @survey
        end
      end
    end
  end
end
