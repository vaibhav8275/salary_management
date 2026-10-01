# devise-jwt signs the bearer token issued on sign-in and verifies it on every
# later request (ARCHITECTURE §7.4, LLD §9.4).
#
# The one setting that has to be made deliberately is the signing secret. Left
# unset, devise-jwt generates one per boot: every token already issued would stop
# verifying, which would sign out every open session whenever the app restarts
# or a second Puma worker came up. A token minted by one process has to verify
# in another.
#
# `JWT_SECRET` is the deployment's own value when it sets one (set it in
# config/deploy.yml or the environment). Otherwise the token is signed with
# `secret_key_base`, which Rails already keeps out of the repository — one per
# environment, in credentials. Both are read at boot; nothing is hardcoded here,
# and no secret is committed.
Devise.jwt do |config|
  config.secret = ENV["JWT_SECRET"].presence || Rails.application.secret_key_base

  # How long a signed token stays usable, in seconds.
  #
  # Left unset this is warden-jwt_auth's default of 3600 (an hour), which is
  # set deliberately here rather than inherited so that the value is visible in
  # one place and can be moved without reading gem source.
  #
  # The window is a security tradeoff with a usability cost on the other side:
  # there is no refresh token and no logout route, so an expired token cannot be
  # renewed at all. When the window closes, the only way back in is to sign in
  # again, and the user sees the login page rather than a half-broken dashboard.
  # That is the correct failure for an HR app holding salary data — a session
  # that lapses while someone walks away from their desk is the point — but it
  # does mean a 30-minute session cannot survive an interview demo that runs
  # longer than that without a re-login.
  config.expiration_time = 30.minutes.to_i
end
