# Be sure to restart your server when you modify this file.

# Handle Cross-Origin Resource Sharing (CORS) so the separate Next.js frontend
# can call this API (ARCHITECTURE §1, LLD §9).
#
# In development the frontend runs on a different port, so localhost origins are
# allowed. In production only the deployed frontend origin is allowed — set
# FRONTEND_ORIGIN, which fails closed rather than defaulting to "*".

frontend_origin = ENV.fetch("FRONTEND_ORIGIN", "http://localhost:3000")

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
