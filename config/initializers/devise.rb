# Devise is configured for exactly one purpose: deciding whether a request
# carries valid HR credentials, and issuing a JWT when it does
# (ARCHITECTURE §7.4, LLD §9.4).
#
# This is deliberately *not* the file `rails generate devise:install` writes.
# Everything Devise does by default suits a server-rendered application with
# sessions, flash messages and HTML sign-in pages. This application is an
# API-only, single-persona backend, so only the settings that this application
# actually had to decide are set; everything not mentioned keeps its default.
Devise.setup do |config|
  # Loads the ActiveRecord integration — the file that gives models the `devise`
  # class method, the `Devise::Models` validations and the `orm_adapter`
  # glue. Devise 5 does not load an ORM adapter on its own; this line is the
  # part of `rails generate devise:install` that is genuinely required.
  require "devise/orm/active_record"

  # Nothing is navigational. Every response is JSON, failures included, so Devise
  # must never answer with a redirect to a login page. This matters more than it
  # looks: Devise treats a `*/*` Accept header — what curl, fetch() and most HTTP
  # clients send — as a browser request, which is exactly how an unauthenticated
  # API call otherwise ends up as a 302 with an HTML body.
  config.navigational_formats = []

  # Warden's default failure app redirects to a login page. An API client needs
  # a status code and the same `errors` envelope every other failure in this
  # application uses, so failures are rendered by `JsonFailureApp`.
  config.warden do |manager|
    manager.failure_app = JsonFailureApp
  end

  # Password hashing cost. 11 is the production setting; the test suite creates
  # and authenticates users on almost every example, where a deliberately slow
  # hash buys nothing except a slow suite.
  config.stretches = Rails.env.test? ? 1 : 11
end
