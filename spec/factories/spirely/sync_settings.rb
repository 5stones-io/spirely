FactoryBot.define do
  factory :spirely_sync_setting, class: "Spirely::SyncSetting" do
    inbound_people_sync  { true }
    outbound_people_sync { false }
    sync_frequency_hours { 6 }
    conflict_resolution  { "pco_wins" }
    auto_sync_enabled    { false }
  end
end
