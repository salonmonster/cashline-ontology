class ComputeDiffJob < ApplicationJob
  queue_as :default

  def perform(run_a_id, run_b_id)
    run_a = ExtractionRun.find(run_a_id)
    run_b = ExtractionRun.find(run_b_id)

    if run_a.content_hash.blank? || run_b.content_hash.blank?
      Rails.logger.warn(
        "[ComputeDiffJob] diffing without verified content_hash " \
        "(run_a=#{run_a.id} #{run_a.content_hash.present? ? 'ok' : 'missing'}, " \
        "run_b=#{run_b.id} #{run_b.content_hash.present? ? 'ok' : 'missing'}) " \
        "— rebuild from JSONL via runs:rebuild_db to verify integrity"
      )
    end

    diff_payload = Ontology::DiffCalculator.compute(run_a, run_b)

    record = RunDiff.find_or_initialize_by(run_a_id: run_a.id, run_b_id: run_b.id)
    record.diff = diff_payload
    record.computed_at = Time.current
    record.save!
    record
  end
end
