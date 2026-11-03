source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.3", ">= 8.1.3.1"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
# gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin Ajax possible
gem "rack-cors"

# Audit trail for salary record changes (LLD §7)
gem "paper_trail", "~> 17.0"

# Background processing for bulk salary imports (LLD §8)
gem "sidekiq", "~> 8.1"

# Required by Rails' :redis_cache_store, which is the cache store in production.
# Sidekiq talks to Redis through redis-client instead, so this is a separate gem.
gem "redis", ">= 4.0.1"

# S3 storage for uploaded CSV files (ARCHITECTURE §4.5)
gem "aws-sdk-s3", require: false

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 1.2"

group :development, :test do
  gem "dotenv-rails", require: false
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  # End-to-end / BDD feature specs (REQUIREMENTS §5, LLD §12)
  gem "cucumber-rails", require: false
  gem "database_cleaner-active_record", require: false

  # Test data for RSpec and Cucumber (LLD §12)
  gem "factory_bot_rails", "~> 6.5"

  # Coverage measurement for the suite (LLD §11).
  gem "simplecov", "~> 1.3", require: false

  gem "rswag-api", "~> 2.17"
  gem "rswag-ui", "~> 2.17"
  gem "rswag-specs", "~> 2.17"

  # json is pinned to the 2.x line, which is where the API schema specs can run.
  #
  # `rswag-specs` validates every example's response body with `json-schema`,
  # and json-schema 6.2.0 (still the latest release) parses it with
  # `JSON.parse(body, quirks_mode: true)`. json 3.0 forwards that option to the
  # native parser as a keyword, which rejects it:
  #
  #   ArgumentError: unknown keyword: quirks_mode
  #
  # The failure happens while reading the body, so it hits every documented
  # response regardless of the request itself and looks like an application bug.
  # json 2.x ignores options it does not know, which is the behaviour
  # json-schema still expects. Rails only requires `json >= 0`, so the pin costs
  # the application nothing.
  #
  # Drop this as soon as json-schema stops passing `quirks_mode`, so the
  # application can move to json 3.x.
  gem "json", "~> 2.21"
end
gem "faker", "~> 3.8"
gem "rspec-rails", "~> 8.0"

gem "blueprinter", "~> 1.3"

# Authentication at the API boundary (ARCHITECTURE §7.4). Devise validates
# credentials, devise-jwt issues and verifies the bearer token; `bcrypt` is the
# password hashing algorithm Devise's `database_authenticatable` uses.
gem "devise", "~> 5.0"
gem "devise-jwt", "~> 0.13.0"
gem "bcrypt", "~> 3.1"
