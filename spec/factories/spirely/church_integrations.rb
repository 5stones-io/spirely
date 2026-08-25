FactoryBot.define do
  factory :spirely_church_integration, class: "Spirely::ChurchIntegration" do
    association :church
    token_type { "oauth" }
  end
end
