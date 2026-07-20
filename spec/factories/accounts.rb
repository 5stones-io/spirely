FactoryBot.define do
  factory :account do
    sequence(:email) { |n| "user#{n}@example.com" }
    status_id { 2 }
    admin { false }

    trait :admin do
      admin { true }
    end
  end
end
