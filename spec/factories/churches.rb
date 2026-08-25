FactoryBot.define do
  factory :church do
    sequence(:slug) { |n| "church#{n}" }
    sequence(:name) { |n| "Church #{n}" }
    enabled_modules { [] }
    status { "approved" }

    trait :pending do
      status { "pending" }
    end

    trait :suspended do
      status { "suspended" }
    end
  end
end
