# Background-processing helpers (LLD §8.3, FR-4.6).
#
# The test environment uses the :test ActiveJob adapter, so "did the API
# enqueue a job?" is answered by inspecting that adapter instead of running a
# real Sidekiq server.
#
# Jobs are executed by calling `perform_now` explicitly rather than through
# `perform_enqueued_jobs`. That keeps the two concerns separate — enqueueing is
# asserted independently from processing — and avoids depending on the
# ActiveJob test-helper lifecycle outside of Minitest.
module ActiveJobHelpers
  def enqueued_jobs
    ActiveJob::Base.queue_adapter.enqueued_jobs
  end

  def performed_jobs
    ActiveJob::Base.queue_adapter.performed_jobs
  end

  # Accepts either the class or its name. The adapter stores the class, but
  # referring to `SalaryImportJob` by name keeps a spec loadable before the job
  # exists, which is the point of writing the test first.
  def jobs_for(klass)
    enqueued_jobs.select { |job| job_name(job) == klass.to_s }
  end

  def job_name(job)
    value = job[:job] || job["job"]
    value.is_a?(Class) ? value.name : value.to_s
  end

  def reset_job_queues!
    adapter = ActiveJob::Base.queue_adapter
    adapter.enqueued_jobs.clear
    adapter.performed_jobs.clear
  end

  # LLD §8.1 — the job is handed the import id alone and resolves the CSV
  # through `salary_imports.s3_object_key`, so that is the only argument here.
  def run_import_job(salary_import)
    SalaryImportJob.perform_now(salary_import.id)
  end
end
