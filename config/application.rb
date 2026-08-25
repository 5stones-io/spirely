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

    # This repo doubles as a standalone runnable app (this class) and, when
    # required as a gem by another app, a mountable Rails::Engine
    # (Spirely::Engine, lib/spirely/engine.rb) — both rooted at the same
    # directory. config/routes.rb holds the engine's real routes
    # (Spirely::Engine.routes.draw, not Rails.application.routes.draw — see
    # that file's own comment for why the latter doesn't work here), so
    # standalone mode needs its own explicit mount to actually reach them,
    # the same way a real host app (spirely-church, kidspire) does.
    initializer :mount_spirely_engine, after: :add_routing_paths do |app|
      app.routes.append do
        mount Spirely::Engine => "/"
      end
    end
  end
end
