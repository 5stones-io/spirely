FactoryBot.define do
  factory :spirely_child, class: "Spirely::Child" do
    # :create, not :build — Child#church_id inherits from family.church_id at
    # validation time, which is nil until the family (and its church) are
    # actually persisted.
    association :family, factory: :spirely_family, strategy: :create
    first_name { Faker::Name.first_name }
    last_name  { Faker::Name.last_name }
    birthdate  { 8.years.ago.to_date }
    grade      { 3 }
  end
end
