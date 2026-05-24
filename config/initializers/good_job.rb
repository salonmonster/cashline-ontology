# GoodJob configuration. Tests use ActiveJob's :test adapter (set in
# `config/environments/test.rb`) so we do not configure a queue adapter here.
#
# Cron entries run via GoodJob's built-in scheduler. The sensitive-run purge
# sweeper runs daily at 03:15 UTC; see PurgeExpiredSensitiveRunsJob.

Rails.application.config.good_job.cron = {
  purge_expired_sensitive_runs: {
    cron: "15 3 * * *",
    class: "PurgeExpiredSensitiveRunsJob",
    description: "Delete sensitive extraction runs (DB + on-disk) whose retained_until has passed."
  }
}
