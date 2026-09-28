# Rswag configuration (API docs + Swagger UI).
#
# rswag-api serves the generated swagger.json; rswag-ui serves the browser UI.
# Both are mounted in config/routes.rb at /api-docs.
Rswag::Api.configure do |c|
  c.openapi_root = Rails.root.join("swagger").to_s
end

Rswag::Ui.configure do |c|
  c.openapi_endpoint "/api-docs/v1/swagger.json", "Salary Management API V1"
end
