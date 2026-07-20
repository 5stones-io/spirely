require "rails/engine"

module Spirely
  class Engine < ::Rails::Engine
    isolate_namespace Spirely

    config.generators do |g|
      g.test_framework :rspec
    end
  end
end
