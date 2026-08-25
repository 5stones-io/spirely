FactoryBot.define do
  factory :membership do
    association :account
    association :church
    role { "family" }

    trait :admin do
      role { "admin" }
    end

    trait :owner do
      role { "owner" }
    end
  end
end
