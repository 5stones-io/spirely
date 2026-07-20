require "rails"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "action_mailer/railtie"
require "active_job/railtie"

Bundler.require(*Rails.groups)

module Spirely
  class Application < Rails::Application
    config.load_defaults 7.2

    config.api_only = false

    config.middleware.use ActionDispatch::Cookies
    config.middleware.use ActionDispatch::Session::CookieStore

    config.active_job.queue_adapter = Rails.env.production? ? :sidekiq : :async
  end
end
