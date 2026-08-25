FactoryBot.define do
  factory :account do
    sequence(:email) { |n| "user#{n}@example.com" }
    status_id { 2 }
  end
end
