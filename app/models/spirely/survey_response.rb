module Spirely
  # One family's answers to a survey (5ST-84). Anonymous: it holds the
  # answers and when they came in, nothing about who sent them.
  # Survey#clean_answers decides what goes in answers.
  class SurveyResponse < ApplicationRecord
    belongs_to :survey, class_name: "Spirely::Survey"
  end
end
