FactoryBot.define do
  factory :spirely_staff_invitation, class: "Spirely::StaffInvitation" do
    association :church
    invited_first_name { "Pat" }
    invited_last_name { "Smith" }
    sequence(:invited_email) { |n| "staffinvite#{n}@example.com" }
  end
end
