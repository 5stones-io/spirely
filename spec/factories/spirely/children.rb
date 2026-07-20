FactoryBot.define do
  factory :spirely_child, class: "Spirely::Child" do
    association :family, factory: :spirely_family
    first_name { Faker::Name.first_name }
    last_name  { Faker::Name.last_name }
    birthdate  { 8.years.ago.to_date }
    grade      { 3 }
  end
end
