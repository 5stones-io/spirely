# PCO Check-Ins' own all-time per-person stats (Person#last_checked_in_at /
# #check_in_count) — unlike Spirely::Attendance, which only ever holds
# PcoAttendanceSyncJob's rolling 16-week window, so "never checked in" can
# finally mean never, not "not in the last 16 weeks".
class AddCheckInStatsToSpirelyPeople < ActiveRecord::Migration[7.2]
  def change
    add_column :spirely_people, :last_checked_in_at, :datetime
    add_column :spirely_people, :check_in_count, :integer
  end
end
