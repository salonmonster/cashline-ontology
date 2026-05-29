module Mapping
  # Adapter that lets Mapping::Evaluator score the *persisted* proposals (after
  # heuristic + embedding + LLM passes) instead of running the raw heuristic
  # matcher. Same `candidates_for` interface, so the evaluator is unchanged.
  # This is how we measure the LLM rerank's lift over the baseline.
  class ProposalCandidates
    def initialize(snapshot)
      @snapshot = snapshot
    end

    def candidates_for(sfield)
      MappingProposal
        .where(source_field_id: sfield.id, cashline_snapshot_id: @snapshot.id, state: %w[open accepted])
        .order(score: :desc)
        .map { |p| { target_class: p.target_class, target_field: p.target_field, score: p.score, signals: p.signals } }
    end
  end
end
