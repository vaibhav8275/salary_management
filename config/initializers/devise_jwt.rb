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
end
