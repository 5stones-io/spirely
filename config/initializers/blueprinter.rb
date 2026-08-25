Blueprinter.configure do |config|
  # Without this, Blueprinter passes Time/Date/ActiveSupport::TimeWithZone
  # values straight through to its default JSON generator (Ruby's stdlib
  # `JSON`, not ActiveSupport's encoder — see Blueprinter::Configuration's
  # own `@generator = JSON` default). Stdlib JSON doesn't know how to
  # serialize a Time and falls back to Object#to_json's `to_s.to_json`,
  # producing Ruby's non-standard "2026-08-08 16:31:55 UTC" instead of
  # ISO 8601 — Chrome/V8's Date parser tolerates that string, but Safari's
  # doesn't, silently rendering "Invalid Date" anywhere a Blueprinter
  # timestamp (SyncSettingBlueprint#last_synced_at, ChildBlueprint/
  # FamilyBlueprint's *_at fields) got parsed client-side. `#iso8601`
  # works for both Time-like and Date-only values, so this is safe for
  # every datetime/date field across every blueprint in the app, not a
  # per-field patch.
  config.datetime_format = ->(value) { value.iso8601 }
end
