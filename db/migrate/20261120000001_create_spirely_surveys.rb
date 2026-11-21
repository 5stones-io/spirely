# Anonymous surveys (5ST-84): a church asks families questions on its own
# site, with no sign-in.
#
# - questions is the survey's list of questions (Spirely::Survey documents
#   the shape); surveys are loaded from templates in config/surveys/.
# - A response is anonymous on purpose: no account, family, person or IP,
#   and no updated_at (nobody edits one).
class CreateSpirelySurveys < ActiveRecord::Migration[7.2]
  def change
    create_table :spirely_surveys do |t|
      t.references :church, null: false, foreign_key: true
      t.string :slug, null: false
      t.string :title, null: false
      t.text :intro
      t.text :thanks
      t.string :home_blurb
      t.jsonb :questions, null: false, default: []
      t.string :status, null: false, default: "open"
      t.boolean :show_on_home, null: false, default: true
      t.datetime :opened_at
      t.datetime :closed_at
      t.timestamps
      t.index [:church_id, :slug], unique: true
    end

    create_table :spirely_survey_responses do |t|
      t.references :survey, null: false, foreign_key: { to_table: :spirely_surveys, on_delete: :cascade }
      t.jsonb :answers, null: false, default: {}
      t.datetime :created_at, null: false
    end
  end
end
