require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false

  config.public_file_server.enabled = true

  config.logger     = ActiveSupport::Logger.new($stdout)
  config.log_level  = ENV.fetch("RAILS_LOG_LEVEL", "info").to_sym
  config.log_tags   = [:request_id]
  # SSL is terminated at Railway's ingress — do not force it at the app level
  config.force_ssl  = false

  config.active_support.report_deprecations = false
  config.active_record.dump_schema_after_migration = false

  # ── Email (magic links) ──────────────────────────────────────────────────
  # Railway blocks all outbound SMTP ports; use Resend's HTTP API instead.
  Resend.api_key = ENV["RESEND_API_KEY"]
  config.action_mailer.delivery_method   = :resend
  config.action_mailer.perform_deliveries = true
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.default_url_options = {
    host:     ENV.fetch("CUSTOM_DOMAIN", ENV.fetch("RAILWAY_PUBLIC_DOMAIN", "localhost")),
    protocol: "https",
  }

  # Use SECRET_KEY_BASE env var directly (Railway sets this; no credentials file needed).
  config.secret_key_base = ENV["SECRET_KEY_BASE"]

  # Host authorization is handled at Railway's ingress level
  config.hosts = nil
end
