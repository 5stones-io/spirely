require "rails_helper"

# Anonymous surveys (5ST-84): what a response may hold, and the results
# staff see.
RSpec.describe Spirely::Survey do
  let(:church) { create(:church) }
  let(:survey) { Spirely::Survey.from_template!(church, "kids_church_family", slug: "year-end-2026") }

  describe ".from_template!" do
    it "loads the Kids Church Family Survey, open and on the home page" do
      expect(survey).to have_attributes(title: "Kids Church Family Survey", status: "open", show_on_home: true)
      expect(survey.questions.size).to eq(12)
      expect(survey.question("safe")).to include("type" => "single", "section" => nil)
      expect(survey.question("enjoys")["options"]).to eq(["Strongly agree", "Agree", "Disagree", "Strongly disagree", "Don't know"])
      expect(survey.question("most_important")).to include("max" => 2, "other" => true)
      expect(survey.opened_at).to be_present
    end

    it "won't take a slug the church already used" do
      survey
      expect { Spirely::Survey.from_template!(church, "kids_church_family", slug: "year-end-2026") }
        .to raise_error(ActiveRecord::RecordInvalid)
    end

    it "raises on a template that doesn't exist" do
      expect { Spirely::Survey.from_template!(church, "nope", slug: "x") }.to raise_error(ArgumentError)
    end
  end

  describe "#clean_answers" do
    it "keeps answers to its own questions, with choices from the list" do
      cleaned = survey.clean_answers(
        "attendance" => { "value" => "Every week" },
        "age_groups" => { "value" => ["Preschool (3-5)", "Made up"] },
        "delivering" => { "value" => "A good job", "follow_up" => "  Great leaders  " },
        "unknown" => { "value" => "x" },
      )
      expect(cleaned).to eq(
        "attendance" => { "value" => "Every week" },
        "age_groups" => { "value" => ["Preschool (3-5)"] },
        "delivering" => { "value" => "A good job", "follow_up" => "Great leaders" },
      )
    end

    it "drops a single choice that isn't on the list, but keeps its follow-up" do
      cleaned = survey.clean_answers("satisfied" => { "value" => "Meh", "follow_up" => "More snacks" })
      expect(cleaned).to eq("satisfied" => { "follow_up" => "More snacks" })
    end

    it "keeps no more choices than a question allows, and the write-in for Other" do
      cleaned = survey.clean_answers(
        "hear_from" => { "value" => ["Email", "Text message", "Social media"] },
        "most_important" => { "value" => ["Bible knowledge", "Other"], "other" => "Kindness" },
      )
      expect(cleaned["hear_from"]).to eq("value" => ["Email", "Text message"])
      expect(cleaned["most_important"]).to eq("value" => ["Bible knowledge", "Other"], "other" => "Kindness")
    end

    it "ignores a write-in when Other isn't picked, or the question has no Other" do
      cleaned = survey.clean_answers(
        "most_important" => { "value" => ["Bible knowledge"], "other" => "Kindness" },
        "hear_from" => { "value" => ["Email", "Other"], "other" => "Carrier pigeon" },
      )
      expect(cleaned["most_important"]).to eq("value" => ["Bible knowledge"])
      expect(cleaned["hear_from"]).to eq("value" => ["Email"])
    end

    it "trims long writing" do
      cleaned = survey.clean_answers("satisfied" => { "follow_up" => "a" * 3000 })
      expect(cleaned["satisfied"]["follow_up"].length).to eq(Spirely::Survey::MAX_TEXT)
    end

    it "takes answers that aren't a hash as nothing" do
      expect(survey.clean_answers("nope")).to eq({})
      expect(survey.clean_answers("attendance" => "Every week")).to eq({})
    end
  end

  describe "#results" do
    it "counts each choice and lists the writing, newest first" do
      survey.responses.create!(answers: survey.clean_answers(
        "attendance" => { "value" => "Every week" },
        "most_important" => { "value" => ["Bible knowledge", "Other"], "other" => "Kindness" },
        "satisfied" => { "value" => "Very satisfied", "follow_up" => "Love it" },
      ))
      survey.responses.create!(answers: survey.clean_answers(
        "attendance" => { "value" => "Every week" },
        "most_important" => { "value" => ["Bible knowledge"] },
        "satisfied" => { "follow_up" => "Longer worship" },
      ), created_at: 1.hour.from_now)

      results = survey.results.index_by { |r| r[:id] }
      expect(results["attendance"]).to include(answered: 2,
        counts: [["Every week", 2], ["Every other week", 0], ["About once a month", 0], ["Occasionally", 0]])
      expect(results["most_important"][:counts]).to include(["Bible knowledge", 2], ["Other", 1])
      expect(results["most_important"][:other]).to eq(["Kindness"])
      expect(results["satisfied"]).to include(answered: 2)
      expect(results["satisfied"][:follow_ups]).to eq(["Longer worship", "Love it"])
      expect(results["safe"]).to include(answered: 0)
    end
  end

  it "is anonymous: a response has nothing about who sent it" do
    expect(Spirely::SurveyResponse.column_names).to contain_exactly("id", "survey_id", "answers", "created_at")
  end
end
