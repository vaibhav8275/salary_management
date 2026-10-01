# Coverage configuration. Loaded by SimpleCov from the project root, so it
# applies to RSpec and Cucumber alike — both load spec/coverage_helper.rb, which
# requires simplecov before the application boots.
#
# Every setting here is written as `SimpleCov.something` rather than as a bare
# call. SimpleCov evaluates this file with `load`, at the top level of `main`,
# not inside a configuration block, so a bare `minimum_coverage 80` raises
# NoMethodError — and because the load is wrapped in a rescue, the file is then
# skipped silently apart from a warning and the run continues with no floor at
# all. That is the worst possible failure for a coverage gate: it looks like it
# is working.
#
# The floor is deliberately below the measured number. A threshold set equal to
# the current result is not a target, it is a tripwire that fires on the first
# honest change — delete one untested line and the build goes red over a
# percentage that did not matter. At this value it catches a real regression and
# still leaves room to raise it as tests are added.
SimpleCov.minimum_coverage 80

SimpleCov.start "rails" do
  # Only `app/` is the application. Everything else here is loaded by requiring
  # the framework rather than by exercising behaviour, so counting it would
  # report coverage of Ruby's own load path.
  add_filter "/spec/"
  add_filter "/features/"
  add_filter "/config/"
  add_filter "/db/"
  add_filter "/vendor/"
  add_filter "/bin/"

  # Grouped so a drop in one area reads as a drop in that area, rather than as a
  # diluted change in a single total.
  add_group "Models", "app/models"
  add_group "Services", "app/services"
  add_group "Jobs", "app/jobs"
  add_group "Controllers", "app/controllers"
  add_group "Serializers", "app/serializers"
  add_group "Blueprints", "app/blueprints"
end

# `app/jobs` carries its own group for a reason worth stating, since it is the
# part of the application it would hurt most to get wrong: the import pipeline.
# A CSV import that half-applies leaves salary records that disagree with the
# file it came from, and reconciling that is manual work on real salary data.
#
# A per-group floor is what this group would ideally enforce, and it is not set
# because simplecov 0.22 has no `minimum_coverage_by_group` — passing one to
# `add_group` raises ArgumentError, and because the load is rescued that fails
# silently and takes the whole file with it, including the floor above.
#
# The group is therefore reporting only. `app/jobs/salary_import_job.rb` is at
# 100% today (44/44), so nothing is being hidden by the omission right now — but
# if it ever regresses, the global number will absorb it silently. Raising this
# to simplecov 1.x, which supports per-group floors, is the fix.
