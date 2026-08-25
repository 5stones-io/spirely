FactoryBot.define do
  factory :spirely_person, class: "Spirely::Person" do
    association :church
    sequence(:pco_person_id) { |n| "pco-person-#{n}" }
    first_name { Faker::Name.first_name }
    last_name  { Faker::Name.last_name }
    child { false }
  end
end
