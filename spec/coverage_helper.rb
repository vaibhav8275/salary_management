# Loaded by RSpec (via .rspec) and by Cucumber (via features/support/env.rb).
#
# Order matters and is the only reason this file exists separately. SimpleCov
# has to be started *before* the application is loaded, otherwise every class
# has already been defined by the time it starts tracking and the reported
# number reflects nothing. `require_relative "../config/environment"` in
# rails_helper is the line that loads the application, so this has to come
# before it — which means it cannot live inside rails_helper itself, because
# rails_helper is what loads the environment.
#
# Both suites load this file, and both load it exactly once. Cucumber runs in its
# own process, so without this guard the two would each call `SimpleCov.start`
# and the second would restart tracking, discarding whatever the first recorded.
if defined?(SimpleCov)
  # A Cucumber run already started it. Do nothing.
elsif ENV["COVERAGE"] == "false"
  # Explicit opt-out, for a machine that only cares whether behaviour passes.
else
  require "simplecov"
  # `.simplecov` holds the configuration, so the floor and filters have one home.
  SimpleCov.start
end
