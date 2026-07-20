FactoryBot.define do
  factory :spirely_guardian, class: "Spirely::Guardian" do
    association :family, factory: :spirely_family
    first_name   { Faker::Name.first_name }
    last_name    { Faker::Name.last_name }
    relationship { "Mother" }
  end
end
