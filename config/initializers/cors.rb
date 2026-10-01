# Be sure to restart your server when you modify this file.

# Handle Cross-Origin Resource Sharing (CORS) so the separate Next.js frontend
# can call this API (ARCHITECTURE §1, LLD §9).
#
# In development the frontend runs on a different port, so localhost origins are
# allowed. In production only the deployed frontend origin is allowed — set
# FRONTEND_ORIGIN, which fails closed rather than defaulting to "*".

# Raises in production rather than falling back, for the same reason as REDIS_URL
# in config/initializers/sidekiq.rb: a default here is indistinguishable from a
# typo, and it fails in a way that looks like a CORS policy problem rather than a
# missing environment variable. Every browser request from the real frontend would
# be rejected against a localhost allow-list, and the browser reports it as a CORS
# error with no hint that the config is at fault.
#
# The localhost default is kept for development, where the frontend genuinely does
# run on a different port. That is the case the default exists to serve.
frontend_origin =
  if Rails.env.production?
    ENV["FRONTEND_ORIGIN"].presence ||
      raise(KeyError, "FRONTEND_ORIGIN is required in production")
  else
    ENV.fetch("FRONTEND_ORIGIN", "http://localhost:3000")
  end

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(*frontend_origin.split(",").map(&:strip))

    resource "*",
      headers: :any,
      methods: [ :get, :post, :put, :patch, :delete, :options, :head ],
      expose: [ "Content-Disposition" ],
      max_age: 600
  end
end
