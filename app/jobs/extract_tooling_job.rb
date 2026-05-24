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
  rescue Salesforce::Error => e
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
