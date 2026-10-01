# Run using bin/ci

CI.run do
  step "Setup", "bin/setup --skip-server"

  step "Style: Ruby", "bin/rubocop"

  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"

  # Cucumber before RSpec, matching .github/workflows/ci.yml. Both write into one
  # merged SimpleCov resultset, so the floor is judged on what the two reach
  # together. The order is not load-bearing, but running them in the same order
  # locally and in CI means the same number appears in both logs — and the merge
  # window is 600s, which both orders fit inside.
  step "Tests: Cucumber", "bundle exec cucumber --publish-quiet"
  step "Tests: RSpec", "bundle exec rspec"

  # Both steps above exit non-zero if the merged line coverage falls under the
  # floor in .simplecov, so there is no separate coverage step here either.

  # Optional: set a green GitHub commit status to unblock PR merge.
  # Requires the `gh` CLI and `gh extension install basecamp/gh-signoff`.
  # if success?
  #   step "Signoff: All systems go. Ready for merge and deploy.", "gh signoff"
  # else
  #   failure "Signoff: CI failed. Do not merge or deploy.", "Fix the issues and try again."
  # end
end
