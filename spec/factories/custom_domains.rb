FactoryBot.define do
  factory :custom_domain do
    association :church
    sequence(:hostname) { |n| "kids#{n}.example-church.org" }

    trait :verified do
      verified_at { Time.current }
    end
  end
end
