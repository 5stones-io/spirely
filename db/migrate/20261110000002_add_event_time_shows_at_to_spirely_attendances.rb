# When check-in opened for each check-in's service time (PCO EventTime
# shows_at, 5ST-75). A time that starts inside a later service's window
# (jccag's 9:00 and 10:10, inside 11:00's 8:30 opening) counts toward
# that later service on the Child sheet.
class AddEventTimeShowsAtToSpirelyAttendances < ActiveRecord::Migration[7.2]
  def change
    add_column :spirely_attendances, :event_time_shows_at, :datetime
  end
end
