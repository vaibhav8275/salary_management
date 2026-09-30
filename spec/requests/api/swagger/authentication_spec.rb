require "swagger_helper"

# The sign-in endpoint is documented separately from the resources it protects:
# it is the only operation that runs without a token (`security: []`), and the
# one whose response is where the token comes from.
RSpec.describe "Authentication API", type: :request do
  path "/api/v1/auth/login" do
    post "Sign in" do
      tags        "Authentication"
      operationId "login"
      consumes    "application/json"
      produces    "application/json"
      # The document declares `bearerAuth` for everything, and this endpoint
      # opts out of it: requiring the token here would document the one call
      # that cannot possibly have it.
      security []
      description <<~DESC
        Exchanges an email address and password for a JWT (LLD §9.4,
        REQUIREMENTS AU-2, AU-3).

        On success the token is returned in the `Authorization` response header as
        `Bearer <jwt>`; the body only says which account signed in. Use the **Authorize**
        button above and paste the token, without the `Bearer ` prefix, to call every
        other endpoint in this API.

        There is no sign-up, sign-out, or password-reset endpoint: the account is
        created by an operator with `bin/rails auth:create_hr_user`.

        Invalid credentials return 401 with the same body whether or not the email
        has an account, so the response cannot be used to discover one (AU-2).
      DESC

      # The body is the whole `LoginRequest`. rswag serializes the `let` named
      # after the body parameter as the entire request body, which is why the
      # `user` wrapper that Devise reads the credentials out of is inside it.
      parameter name: :body, in: :body, required: true,
                schema: { "$ref" => "#/components/schemas/LoginRequest" }

      response "200", "credentials accepted" do
        schema type: :object,
               properties: {
                 data: { "$ref" => "#/components/schemas/SignedInUser" }
               },
               required: %w[data]

        # The account is a separate `let` so it does not collide with the body.
        let(:account) { create(:user) }
        let(:body) do
          { user: { email: account.email, password: "correct-horse-battery-staple" } }
        end
        before { anonymous_caller! }

        run_test!
      end

      response "401", "invalid credentials" do
        schema "$ref" => "#/components/schemas/ErrorEnvelope"

        let(:body) { { user: { email: "nobody@example.com", password: "not-the-password" } } }
        before { anonymous_caller! }

        run_test!
      end
    end
  end
end
