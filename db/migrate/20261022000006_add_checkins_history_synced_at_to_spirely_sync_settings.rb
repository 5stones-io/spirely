# The Check-Ins sync normally re-reads a 16-week window. The first time it
# runs for a church it reads 26 weeks instead, so Kudos can pay for check-ins
# back that far; this records when that catch-up happened.
class AddCheckinsHistorySyncedAtToSpirelySyncSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :spirely_sync_settings, :checkins_history_synced_at, :datetime
  end
end
