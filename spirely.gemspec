require_relative "lib/spirely/version"

Gem::Specification.new do |spec|
  spec.name        = "spirely"
  spec.version     = Spirely::VERSION
  spec.authors     = ["Chad Singleton"]
  spec.email       = ["hello@5stones.io"]
  spec.summary     = "Identity, profile, and Planning Center Online sync engine for the 5stones.io church-software suite"
  spec.description = "Open source identity and profile provider. Rodauth-powered passwordless auth, self-hosted Ory Hydra for OAuth2/OIDC federation across 5stones.io apps, and bidirectional Planning Center Online people sync."
  spec.homepage    = "https://5stones.io/spirely"
  spec.license     = "MIT"

  spec.metadata = {
    "homepage_uri"      => "https://5stones.io/spirely",
    "source_code_uri"   => "https://github.com/5stones-io/spirely",
    "bug_tracker_uri"   => "https://github.com/5stones-io/spirely/issues"
  }

  spec.files = Dir[
    "app/**/*",
    "config/**/*",
    "db/**/*",
    "lib/**/*",
    "LICENSE",
    "README.md"
  ]

  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 3.3"

  spec.add_dependency "rails",         "~> 7.2"
  spec.add_dependency "pg",           "~> 1.5"
  spec.add_dependency "rodauth-rails", "~> 1.0"
  spec.add_dependency "jwt"
  spec.add_dependency "bcrypt",        "~> 3.1"
  spec.add_dependency "blueprinter"
  spec.add_dependency "sidekiq",     "~> 7.0"
  spec.add_dependency "redis",      "~> 5.0"
  spec.add_dependency "httparty"
  spec.add_dependency "rack-cors"
  spec.add_dependency "rack-attack"
  spec.add_dependency "kaminari"

  spec.add_development_dependency "gem-release"
end
