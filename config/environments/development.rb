require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.server_timing = true

  config.active_support.deprecation = :log
  config.active_support.disallowed_deprecation = :raise
  config.active_support.disallowed_deprecation_warnings = []

  config.active_record.migration_error = :page_load
  config.active_record.verbose_query_logs = true

  # Mail: magic link URLs are always logged to Rails console (look for 🔐).
  # To also catch emails in a UI, run MailHog on port 1025 and set SMTP_ADDRESS=localhost.
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.perform_deliveries = true
  config.action_mailer.raise_delivery_errors = false
  config.action_mailer.smtp_settings = {
    address: ENV.fetch("SMTP_ADDRESS", "localhost"),
    port:    ENV.fetch("SMTP_PORT", 1025).to_i,
  }
  config.action_mailer.default_url_options = { host: "localhost", port: 3000 }
end
