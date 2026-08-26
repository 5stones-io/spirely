require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = false
  config.consider_all_requests_local = true
  config.cache_store = :null_store

  config.action_dispatch.show_exceptions = :rescuable

  # Bridge::* controllers (Hydra login/consent) are ActionController::Base
  # with real forms — disable CSRF enforcement in tests like a standard
  # Rails app does, so request specs can POST directly without a token.
  config.action_controller.allow_forgery_protection = false

  config.action_mailer.perform_caching = false
  config.action_mailer.delivery_method = :test

  config.active_support.deprecation = :stderr
  config.active_support.disallowed_deprecation = :raise
  config.active_support.disallowed_deprecation_warnings = []

  config.active_record.migration_error = :page_load
  config.active_record.dump_schema_after_migration = false

  config.active_storage.service = :test
end
