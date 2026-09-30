# Renders Devise/Warden authentication failures as a 401 in the API's own error
# envelope instead of redirecting to a login page.
#
# Without this, an unauthenticated call to a protected endpoint gets a 302 with
# an HTML body: a status code that tells an API client nothing about what went
# wrong, pointing at a login page that does not exist in an API-only
# application. The body has to match the envelope `ApplicationController` already
# uses for every other failure, so a client parses 401s and 404s the same way:
#
#   401 → { "errors": [ { "code": "unauthorized", "message": "..." } ] }
#
# 401 rather than 403 is the point: the caller is told it is unauthenticated,
# which is the one thing it has to know — the remedy is to sign in again.
#
# One message serves every failure: missing token, malformed token, expired
# token, wrong password, unknown email. The differences are not disclosed because
# an attacker can use them to learn which email addresses have accounts, and a
# caller does not need them — it already knows which endpoint it called, so it
# knows whether to re-prompt for credentials or to send the user back to the
# login screen.
class JsonFailureApp
  CODE = "unauthorized"
  MESSAGE = "authentication required"

  # Warden calls this on whatever `manager.failure_app` was set to
  # (config/initializers/devise.rb), so it has to be a class method — the same
  # shape as the `Devise::FailureApp` it replaces.
  def self.call(_env)
    [ 401, headers, [ body ] ]
  end

  def self.headers
    # A new hash per call: Rack::ETag mutates the response headers it is given,
    # so a shared frozen constant would blow up on the first 401.
    { "Content-Type" => "application/json" }
  end

  def self.body
    JSON.generate(errors: [ { code: CODE, message: MESSAGE } ])
  end

  private_class_method :headers, :body
end
