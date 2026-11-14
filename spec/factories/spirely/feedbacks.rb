FactoryBot.define do
  factory :spirely_feedback, class: "Spirely::Feedback" do
    association :church
    association :account
    category { "general" }
    body { "Thank you for the new check-in stickers!" }
    sender_role { "member" }
  end
end
