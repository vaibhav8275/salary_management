# Sidekiq configuration — ARCHITECTURE §4.3
#
# Sidekiq owns every long-running task. Bulk salary imports enqueue a job with
# the salary_import id and return immediately; the worker does the CSV reading
# and the writes (LLD §8.1, §8.3).

REDIS_URL_DEFAULT = ENV.fetch("REDIS_URL", "redis://localhost:6379/0").freeze

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
