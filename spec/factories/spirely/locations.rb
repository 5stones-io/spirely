FactoryBot.define do
  factory :spirely_location, class: "Spirely::Location" do
    association :church
    sequence(:pco_location_id) { |n| "location-#{n}" }
    name { "Nursery" }
  end
end
