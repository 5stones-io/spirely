# Which Planning Center service time (EventTime) each check-in was for
# (5ST-75), so attendance can be shown per service: one event like
# "JCC Kidz" can run Sunday 11 AM, Sunday 6 PM and Wednesday 7 PM.
# day_of_week/hour/minute are PCO's own church-local values, so grouping
# by service doesn't depend on the church's time zone setting.
class AddEventTimeToSpirelyAttendances < ActiveRecord::Migration[7.2]
  def change
    add_column :spirely_attendances, :pco_event_time_id, :string
    add_column :spirely_attendances, :event_time_starts_at, :datetime
    add_column :spirely_attendances, :event_time_name, :string
    add_column :spirely_attendances, :event_time_day_of_week, :integer
    add_column :spirely_attendances, :event_time_hour, :integer
    add_column :spirely_attendances, :event_time_minute, :integer
    add_index :spirely_attendances, [:church_id, :pco_event_time_id]
  end
end
