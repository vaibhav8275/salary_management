require "devise/jwt/test_helpers"

# Signing in for RSpec request specs and Cucumber scenarios (LLD §9.4).
#
# There is one account and one persona, so the helper builds a single HR user and
# hands back the two things a caller needs: the token, and the header carrying it.
#
# The token is minted with devise-jwt's own test helper rather than by POSTing to
# the login endpoint. That is the right default for nearly every example: it
# costs no password hashing and no HTTP round trip, and those examples are about
# the application's behaviour, not about login. The login examples
# (spec/requests/api/authentication_spec.rb) do sign in over HTTP, so the endpoint
# and the token it dispatches are still covered end to end.
module AuthenticationHelpers
  # The header a client sends after signing in.
  def auth_headers(user = hr_manager)
    anonymous_caller? ? {} : { "Authorization" => "Bearer #{auth_token(user)}" }
  end

  # The bare token, without the `Bearer` prefix.
  def auth_token(user = hr_manager)
    token = Devise::JWT::TestHelpers.auth_headers({}, user).fetch("Authorization")
    token.delete_prefix("Bearer ")
  end

  # The account that can reach the API. Memoised so a single example that makes
  # several requests signs in once.
  def hr_manager
    @hr_manager ||= create(:user)
  end

  # Turns the rest of the example into an unauthenticated caller, so the next
  # request is made the way a client without a token makes it. Used by the
  # examples that assert on the 401 side of the boundary.
  def anonymous_caller!
    @anonymous_caller = true
  end

  def anonymous_caller?
    @anonymous_caller == true
  end
end

# Attaches the bearer token to every request in a request-spec example.
#
# rspec-rails sends every `get`/`post`/... in an example through one integration
# session, so these overrides are the single place the header has to be added.
# The alternative — passing `headers:` at each of the several hundred request
# specs — would bury the one line that describes the boundary in noise, and would
# leave "authenticated" as something each example has to remember rather than the
# default it should be.
#
# A header passed explicitly by an example still wins, and `anonymous_caller!`
# turns the token off for the examples that are about its absence.
module AuthenticatedRequestVerbs
  %w[get post patch put head delete options].each do |verb|
    define_method(verb) do |*args, **options, &block|
      options[:headers] = auth_headers.merge(options[:headers] || {})
      super(*args, **options, &block)
    end
  end
end
