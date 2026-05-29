class ExtractToolingJob < ApplicationJob
  queue_as :default

  # Per-run job that augments the run directory with Tooling-API-only metadata:
  # formula source text and validation rule logic. Runs after ExtractDescribeJob
  # so that the per-object JSONL already exists and we can append additional
  # `record_type: "tooling_field_metadata"` lines to each file.
  def perform(extraction_run_id)
    run = ExtractionRun.find(extraction_run_id)
    rd = Runs::RunDirectory.for(run)

    fetcher = build_fetcher

    visited_objects(rd).each do |api_name|
      begin
        records = fetcher.fetch_for(api_name)
        records.each do |record|
          rd.append_jsonl!(rd.object_jsonl_path(api_name), record)
        end
      rescue Salesforce::Error => e
        run.record_partial_failure!(object_api_name: api_name, reason: "tooling: #{e.message}")
      end
    end

    # Pipeline finalization. The on-disk JSONL is the source of truth; load it
    # into the relational tables, fan out per-object profiling jobs, stamp a
    # content_hash from the directory contents, and mark the run complete.
    # Profiling is fire-and-forget — ObjectProfile rows populate independently
    # while the run is already marked complete.
    Runs::RelationalLoader.load!(run)

    # Derive relationship clusters so object-role context (the cluster a field's
    # object belongs to) is available to the mapping dossiers and the cluster
    # map. Non-fatal: a clustering hiccup must not fail an otherwise-complete
    # extraction, and it skips runs whose clusters a user has hand-edited.
    begin
      Ontology::ClusterPersister.compute_and_persist!(run)
    rescue StandardError => e
      Rails.logger.warn("[ExtractToolingJob] clustering skipped: #{e.class}: #{e.message}")
    end

    run.sobjects.pluck(:id).each do |sobject_id|
      ProfileObjectJob.perform_later(sobject_id)
    end

    run.mark_complete!(content_hash: rd.content_digest)
  rescue Salesforce::Error, ActiveRecord::ActiveRecordError, IOError, SystemCallError => e
    run&.mark_failed!(e.message)
    raise
  end

  private

  # Seam for tests: override to inject a fake fetcher without stubbing modules.
  def build_fetcher
    Salesforce::ToolingFetcher.new(client: Salesforce::ClientFactory.tooling)
  end

  def visited_objects(rd)
    return [] unless File.exist?(rd.manifest_path)
    JSON.parse(File.read(rd.manifest_path)).fetch("objects_visited", [])
  end
end
