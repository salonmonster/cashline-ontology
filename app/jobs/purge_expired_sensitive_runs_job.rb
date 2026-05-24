class PurgeExpiredSensitiveRunsJob < ApplicationJob
  queue_as :default

  # Runs daily via the cron entry below in `config/good_job.yml`. Deletes both
  # the on-disk directory and the DB row for any sensitive extraction run whose
  # retained_until has passed. Non-sensitive runs are kept indefinitely.
  def perform
    ExtractionRun.purgeable.find_each do |run|
      Runs::RunDirectory.for(run).purge!
      run.destroy!
    end
  end
end
