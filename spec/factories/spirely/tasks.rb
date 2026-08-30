FactoryBot.define do
  factory :spirely_task, class: "Spirely::Task" do
    association :church
    sequence(:title) { |n| "Task #{n}" }
    status { "not_started" }
  end
end
