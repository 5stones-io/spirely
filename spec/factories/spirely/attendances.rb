FactoryBot.define do
  factory :spirely_attendance, class: "Spirely::Attendance" do
    association :person, factory: :spirely_person, strategy: :create
    sequence(:pco_check_in_id) { |n| "checkin-#{n}" }
    pco_event_id { "event-1" }
    event_name   { "Sunday Service" }
    checked_in_at { Time.current }
    kind { "regular" }
  end
end
