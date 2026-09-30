require "rails_helper"

# LLD §9.4 — the authentication boundary. Everything else in this application
# sits behind these examples: `ApplicationController` requires a token, so if
# signing in stopped working every other request spec would fail, and if the
# boundary leaked, the 401 examples here would.
#
# The examples assert the observable contract rather than Devise's internals: a
# token in the `Authorization` response header, a 401 in the standard `errors`
# envelope, and the absence of the endpoints that are out of scope.
RSpec.describe "API authentication", type: :request do
  # `travel_to` for the expired-token example: the JWT carries an `exp` claim and
  # the decoder compares it with the current time, so moving the clock forward
  # past the token's lifetime is how an expiry is produced without waiting.
  include ActiveSupport::Testing::TimeHelpers

  describe "POST /api/v1/auth/login" do
    it "authenticates valid credentials" do
      user = hr_manager

      post "/api/v1/auth/login", params: { user: { email: user.email, password: "correct-horse-battery-staple" } }, as: :json

      expect(response).to have_http_status(:ok)
      expect(api_data).to include("email" => user.email)
    end

    it "returns a JWT in the Authorization response header" do
      user = hr_manager

      post "/api/v1/auth/login", params: { user: { email: user.email, password: "correct-horse-battery-staple" } }, as: :json

      # devise-jwt dispatches the token as `Bearer <jwt>`, so the value is
      # header.base64url(header).base64url(payload).base64url(signature).
      header = response.headers["Authorization"]
      expect(header).to be_present
      expect(header).to start_with("Bearer ")
      expect(header.delete_prefix("Bearer ").split(".").length).to eq(3)
    end

    it "does not put the token in the response body" do
      user = hr_manager

      post "/api/v1/auth/login", params: { user: { email: user.email, password: "correct-horse-battery-staple" } }, as: :json

      # The body says who signed in. It must not carry the credential digest,
      # and the token is read from the header rather than duplicated here.
      expect(api_data.keys).to eq(%w[email])
    end

    it "rejects a wrong password" do
      user = hr_manager

      post "/api/v1/auth/login", params: { user: { email: user.email, password: "not-the-password" } }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects an email that has no account" do
      post "/api/v1/auth/login", params: { user: { email: "nobody@example.com", password: "correct-horse-battery-staple" } }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it "does not disclose whether the email exists" do
      user = hr_manager

      post "/api/v1/auth/login", params: { user: { email: user.email, password: "not-the-password" } }, as: :json
      wrong_password = api_response_body

      post "/api/v1/auth/login", params: { user: { email: "nobody@example.com", password: "correct-horse-battery-staple" } }, as: :json
      unknown_email = api_response_body

      # Identical bodies, or the endpoint reports which addresses have accounts.
      expect(wrong_password).to eq(unknown_email)
    end

    it "issues no token when the credentials are wrong" do
      user = hr_manager

      post "/api/v1/auth/login", params: { user: { email: user.email, password: "not-the-password" } }, as: :json

      expect(response.headers["Authorization"]).to be_nil
    end
  end

  describe "the token end to end" do
    it "authenticates a request made with the dispatched token" do
      user = hr_manager

      post "/api/v1/auth/login", params: { user: { email: user.email, password: "correct-horse-battery-staple" } }, as: :json
      token = response.headers["Authorization"]

      anonymous_caller!
      headers = auth_headers(user).merge("Authorization" => token)

      get "/api/v1/employees", headers: headers

      expect(response).to have_http_status(:ok)
    end
  end

  describe "requests without a usable token" do
    it "returns 401 when no token is sent" do
      anonymous_caller!

      get "/api/v1/employees"

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 when the token is not a JWT" do
      anonymous_caller!

      get "/api/v1/employees", headers: { "Authorization" => "Bearer not-a-jwt" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 when the token is signed with a different secret" do
      anonymous_caller!
      forged = JWT.encode({ "sub" => hr_manager.id.to_s, "exp" => 1.hour.from_now.to_i }, "a-different-secret", "HS256")

      get "/api/v1/employees", headers: { "Authorization" => "Bearer #{forged}" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 when the token has expired" do
      anonymous_caller!
      token = auth_token

      travel_to 2.hours.from_now do
        get "/api/v1/employees", headers: { "Authorization" => "Bearer #{token}" }
      end

      expect(response).to have_http_status(:unauthorized)
    end

    it "reports the failure in the standard error envelope" do
      anonymous_caller!

      get "/api/v1/employees"

      expect(api_errors.first).to include("code" => "unauthorized")
    end

    it "protects write endpoints too" do
      anonymous_caller!
      employee = create(:employee)

      post "/api/v1/employees/#{employee.id}/salary", params: { salary_record: { base_salary: "1" } }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "an authenticated caller" do
    it "reaches the application as before" do
      create(:employee, first_name: "Ada", last_name: "Lovelace")

      get "/api/v1/employees"

      expect(response).to have_http_status(:ok)
      expect(api_data.first).to include("name" => "Ada Lovelace")
    end
  end

  describe "endpoints that are out of scope" do
    it "does not expose sign up" do
      anonymous_caller!

      post "/api/v1/users"

      expect(response).to have_http_status(:not_found)
    end

    it "does not expose sign out" do
      delete "/api/v1/auth/logout"

      expect(response).to have_http_status(:not_found)
    end

    it "leaves the health check reachable without a token" do
      anonymous_caller!

      get "/up"

      # A load balancer has no credentials to send, so the health check is
      # deliberately outside the authenticated surface.
      expect(response).to have_http_status(:ok)
    end
  end
end
