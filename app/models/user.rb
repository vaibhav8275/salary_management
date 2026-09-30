# An account that can reach the API.
#
# One model and no roles: this system serves a single HR persona, so being
# authenticated *is* being the HR user. There is nothing to authorize, which is
# why no role column, policy object or permission check exists anywhere in the
# application.
#
# Only the modules authentication actually needs are enabled:
#
#   :database_authenticatable — compares the submitted password against the
#                                stored bcrypt digest
#   :jwt_authenticatable       — issues the bearer token on sign-in and
#                                authenticates later requests from the
#                                `Authorization: Bearer` header (devise-jwt)
#   :validatable               — email format and uniqueness, password length
#
# Deliberately absent:
#
#   :registerable  — there is no sign-up. The HR account is created backend-side
#                    by `rails auth:create_hr_user`, so a registration route
#                    would be an unauthenticated write to this table.
#   :recoverable, :confirmable
#                  — both need mail delivery to work, and an API-only app with
#                    no mailer configured would fail silently instead of
#                    sending the message.
#   :rememberable, :lockable — out of scope.
#
# No JWT revocation strategy is configured either: logout is out of scope, so a
# token stays valid until it expires. `Null` says that explicitly —
# devise-jwt ships the null-object strategy for exactly this case, and without a
# strategy named here the gem has no default to fall back on.
class User < ApplicationRecord
  devise :database_authenticatable,
         :jwt_authenticatable,
         :validatable,
         jwt_revocation_strategy: Devise::JWT::RevocationStrategies::Null
end
