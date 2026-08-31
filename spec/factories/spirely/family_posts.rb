FactoryBot.define do
  factory :spirely_family_post, class: "Spirely::FamilyPost" do
    association :church
    association :family, factory: :spirely_family, strategy: :create
    body { "Please pray for our family this week." }
  end
end
