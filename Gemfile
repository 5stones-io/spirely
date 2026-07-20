source "https://rubygems.org"

ruby "~> 3.3"

gemspec

gem "puma",          ">= 5.0"
gem "rodauth-rails", "~> 1.0"
gem "jwt"
gem "kaminari"
gem "blueprinter"
gem "httparty"
gem "sidekiq",        "~> 7.0"
gem "connection_pool", "~> 2.0"               # 3.x breaks Ruby 3.3
gem "redis",          "~> 5.0"
gem "rack-cors"
gem "rack-attack"
gem "resend"

gem "bootsnap", require: false
gem "dotenv-rails", groups: [:development, :test]

group :development, :test do
  gem "debug", platforms: %i[mri mswin]
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "faker"
  gem "webmock"
end

group :development do
  gem "rubocop-rails-omakase", require: false
end
