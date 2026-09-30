# Rswag configuration (API docs + Swagger UI).
#
# rswag-api serves the generated swagger.json; rswag-ui serves the browser UI.
# Both are mounted in config/routes.rb at /api-docs.
#
# The gems are in the development/test group, so in production `Rswag` is not
# defined and the whole file below would raise NameError during boot. An
# initializer is the wrong place to make that conditional by rescuing, so the
# constant is checked first and production skips straight past it.
return unless defined?(Rswag::Api) && defined?(Rswag::Ui)

Rswag::Api.configure do |c|
  c.openapi_root = Rails.root.join("swagger").to_s
end

Rswag::Ui.configure do |c|
  c.openapi_endpoint "/api-docs/v1/swagger.json", "Salary Management API V1"
end
