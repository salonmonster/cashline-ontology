module Mapping
  # Scores a matcher against the hand-confirmed gold set (Mapping::GoldSet).
  #
  # The gold data is entity-level (source object -> acceptable target classes),
  # but the matcher is field-level. So we aggregate: for each gold source object
  # we run the matcher over all its fields and sum candidate scores per target
  # class. The object's predicted target is the highest-scoring class. This makes
  # "do the field suggestions collectively point at the right cashline model?"
  # measurable as entity precision@1 / recall@K — the baseline to beat before the
  # LLM-adjudication stage lands.
  class Evaluator
    Result = Data.define(:source_object, :gold_targets, :ranked, :hit_at_1, :hit_at_k, :top_score)

    # Aggregate class score above which a gap object counts as a (wrong) confident home.
    FALSE_CONFIDENCE = 1.0

    def initialize(run:, snapshot:, matcher: nil, top_k: 3)
      @run = run
      @snapshot = snapshot
      @matcher = matcher || HeuristicMatcher.new(snapshot: snapshot)
      @top_k = top_k
      @gold = GoldSet.new
    end

    def call
      mapped = @gold.mapped.map { |e| evaluate(e) }
      gaps = @gold.no_target.map { |e| evaluate(e) }
      {
        mapped: mapped,
        no_target: gaps,
        precision_at_1: ratio(mapped, &:hit_at_1),
        recall_at_k: ratio(mapped, &:hit_at_k),
        false_confident_gaps: gaps.count { |r| r.top_score.to_f >= FALSE_CONFIDENCE }
      }
    end

    # [[class, score], ...] descending — sum of candidate scores per target class.
    # Pure function so the aggregation is unit-testable without a DB.
    def self.rank_classes(candidate_lists)
      scores = Hash.new(0.0)
      candidate_lists.each do |cands|
        Array(cands).each { |c| scores[c[:target_class]] += c[:score].to_f }
      end
      scores.sort_by { |_, v| -v }
    end

    private

    def evaluate(entry)
      sobject = @run.sobjects.find_by(api_name: entry.source_object)
      ranked = sobject ? self.class.rank_classes(candidate_lists(sobject)) : []
      top_classes = ranked.first(@top_k).map(&:first)
      Result.new(
        source_object: entry.source_object,
        gold_targets: entry.targets,
        ranked: ranked.first(@top_k),
        hit_at_1: entry.targets.any? && entry.targets.include?(top_classes.first),
        hit_at_k: entry.targets.any? && (top_classes & entry.targets).any?,
        top_score: ranked.first&.last
      )
    end

    def candidate_lists(sobject)
      sobject.sfields.includes(:spicklist_values).map { |sf| @matcher.candidates_for(sf) }
    end

    def ratio(results)
      scored = results.select { |r| r.gold_targets.any? }
      return 0.0 if scored.empty?
      (scored.count { |r| yield(r) }.to_f / scored.size).round(3)
    end
  end
end
