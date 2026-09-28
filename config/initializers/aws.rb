# S3 configuration — ARCHITECTURE §4.5
#
# The API uploads the bulk-import CSV to S3 and the Sidekiq worker reads it back,
# so the file never passes through the API/worker boundary or lives on local disk.
# `SalaryImport.s3_object_key` (LLD §2.5) holds the key of that object.

Rails.application.config.x.s3 = {
  region: ENV.fetch("AWS_REGION", "us-east-1"),
  bucket: ENV.fetch("S3_BUCKET", "salary-management-imports"),
  # Credentials are resolved by the AWS SDK's default chain (env vars, shared
  # config, instance/task role) — never hard-coded here.
  force_path_style: ENV.fetch("S3_FORCE_PATH_STYLE", "false") == "true"
}
