FactoryBot.define do
  factory :spirely_invitation, class: "Spirely::Invitation" do
    association :family, factory: :spirely_family, strategy: :create
  end
end
