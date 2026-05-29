# Reranks the open mapping proposals for a (run, snapshot) with the LLM
# adjudicator (Stage 2). Runs after the heuristic pass — and after embeddings
# when those run — so it reranks the full candidate set. Degrades to a no-op
# when Anthropic isn't configured; the heuristic/embedding scores stand.
class ComputeLlmAdjudicationJob < ApplicationJob
  queue_as :default

  if respond_to?(:good_job_control_concurrency_with)
    good_job_control_concurrency_with(
      total_limit: 1,
      key: -> { "compute_llm_adjudication:#{arguments.first}:#{arguments.second}" }
    )
  end

  def perform(extraction_run_id, cashline_snapshot_id)
    run = ExtractionRun.find(extraction_run_id)
    snapshot = CashlineSnapshot.find(cashline_snapshot_id)

    adjudicator = build_adjudicator(snapshot)
    return unless adjudicator.available? # no credentials → heuristic/embedding stands

    adjudicator.combine!(run)
    # Resolve many-to-one collisions: one winner per contested cashline target.
    Mapping::LlmDisambiguator.new(snapshot: snapshot).resolve!(run)
  rescue Anthropic::Error, Faraday::Error => e
    Rails.logger.warn("[ComputeLlmAdjudicationJob] degraded to non-LLM scoring: #{e.class}: #{e.message}")
  end

  private

  # Test seam — override to inject a fake adjudicator.
  def build_adjudicator(snapshot)
    Mapping::LlmAdjudicator.new(snapshot: snapshot)
  end
end
