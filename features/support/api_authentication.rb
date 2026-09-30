# Signs every scenario in as the authenticated HR caller (LLD §9.4).
#
# Scenarios describe what the HR Manager can do, and every route of this API
# requires a token, so the header is registered once for all of them rather than
# repeated in every feature. Nothing here teaches the steps about authentication —
# they read the API exactly as the RSpec request specs do, which is the point of
# keeping authentication out of the behaviour being described.
#
# This file follows the same pattern as `factories.rb`: it shares the RSpec
# authentication helper so both suites mint the same kind of token, and it has no
# hook of its own. The scenario-level setup belongs in `hooks.rb`, whose `Before`
# runs after database_cleaner has opened the transaction — a token is only
# useful in a scenario if the user behind it is rolled back with the rest of the
# scenario's data.
require Rails.root.join("spec/support/authentication_helpers")

World(AuthenticationHelpers)
