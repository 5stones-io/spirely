class AddBrandingToChurches < ActiveRecord::Migration[7.2]
  def change
    # Nullable, falls back to `name` when blank — a church's real legal/
    # display name (used in emails, the Public Mini-Site, etc.) isn't
    # always what they want showing next to their logo in the app shell's
    # top-left brand mark (e.g. a shorter nickname). Logo itself is an
    # Active Storage attachment (has_one_attached :logo on Church), not a
    # column here — the host app's own active_storage_* tables already
    # exist (added for Incident photos), nothing new needed for that part.
    add_column :churches, :display_name, :string
  end
end
