class PurgeExpiredSensitiveRunsJob < ApplicationJob
  queue_as :default

  # Runs daily via GoodJob cron (see config/initializers/good_job.rb).
  # Deletes both the on-disk directory and the DB row for any sensitive
  # extraction run whose retained_until has passed. Non-sensitive runs are
  # kept indefinitely.
  #
  # Per-run isolation: a single failure must not abort the daily sweep.
  # Order is FS-first, then DB destroy: if FS purge succeeds but DB
  # destroy fails, the next daily run retries (purge! is idempotent —
  # no-op when the directory is already gone). The opposite ordering
  # could orphan an FS directory if DB destroy succeeded and FS purge
  # then failed.
  def perform
    failed = []
    ExtractionRun.purgeable.find_each do |run|
      begin
        Runs::RunDirectory.for(run).purge!
        run.destroy!
      rescue StandardError => e
        failed << { id: run.id, token: run.directory_token, error: "#{e.class}: #{e.message}" }
        Rails.logger.error(
          "[PurgeExpiredSensitiveRunsJob] run #{run.id} (#{run.directory_token}) " \
          "failed to purge: #{e.class}: #{e.message}"
        )
      end
    end
    failed
  end
end
