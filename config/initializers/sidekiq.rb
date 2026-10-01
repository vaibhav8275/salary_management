# Sidekiq configuration — ARCHITECTURE §4.3
#
# Sidekiq owns every long-running task. Bulk salary imports enqueue a job with
# the salary_import id and return immediately; the worker does the CSV reading
# and the writes (LLD §8.1, §8.3).

# Sidekiq has to reach Redis, and the address differs by environment: a local
# sidekiq on the same machine in development, a Kamal accessory container in
# production.
#
# The production branch raises rather than falling back. `ENV.fetch` with a default
# cannot tell "not configured" apart from "misspelled", and here both would produce
# redis://localhost:6379/0 -- which from inside the app container means the app
# container. That failure is indistinguishable from Redis being down:
# CannotConnectError: connect(2) for 127.0.0.1:6379, which is exactly what kept the
# job role crash-looping while the accessory was healthy. Naming the missing
# variable at boot is the difference between a five-second fix and an afternoon
# spent looking at Redis.
#
# Redis follows this pattern in config/database.yml, where the production host also
# raises instead of defaulting.
redis_url =
  if Rails.env.production?
    ENV["REDIS_URL"].presence ||
      raise(KeyError, "REDIS_URL is required in production")
  else
    ENV.fetch("REDIS_URL", "redis://localhost:6379/0")
  end

REDIS_URL_DEFAULT = redis_url.freeze

Sidekiq.configure_server do |config|
  config.redis = { url: REDIS_URL_DEFAULT }

  # A failed job is a data-integrity concern (LLD §8.2 tracks import failure), so
  # log the job and its arguments rather than letting the failure vanish.
  config.error_handlers << lambda do |exception, context|
    Rails.logger.error(
      "Sidekiq job failed: #{context[:job]&.class} " \
      "jid=#{context[:jid]} error=#{exception.class}: #{exception.message}"
    )
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: REDIS_URL_DEFAULT }
end
