module Api
  module V1
    # Sign in: credentials in, bearer token out.
    #
    # Devise's sessions controller does the actual work — it is `POST
    # /api/v1/auth/login` that `warden.authenticate!` runs against, and Devise
    # is what compares the submitted password with the stored bcrypt digest.
    # This subclass only shapes the response, because Devise answers a
    # successful sign-in with a redirect to a sign-in page, and an API client
    # needs a small JSON body instead.
    #
    # Sign out is deliberately absent: logout is out of scope, so no route is
    # declared for it (config/routes.rb) and this controller inherits no `destroy`
    # action worth calling. Tokens are not revoked — a token stays valid until it
    # expires.
    class SessionsController < Devise::SessionsController
      # `warden.authenticate!` is also what mints the token: devise-jwt hooks
      # Warden's authentication callback and writes the JWT into the
      # `Authorization` *response* header for this request only (the path and
      # verb are matched against `dispatch_requests`, configured from the
      # `devise_for` declaration). The body below therefore does not repeat the
      # token, and the client reads it from the header.
      #
      # On invalid credentials `authenticate!` throws `:warden`, which
      # `JsonFailureApp` renders as a 401 — so this method only ever runs for a
      # successful sign-in.
      def create
        self.resource = warden.authenticate!(auth_options)

        # The account that was authenticated, and nothing else: rendering the
        # `User` record would serialize `encrypted_password` into the response.
        render json: { data: { email: resource.email } }, status: :ok
      end
    end
  end
end
