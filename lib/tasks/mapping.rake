namespace :mapping do
  def resolve_run_and_snapshot
    run = ENV["RUN"] ? ExtractionRun.find(ENV["RUN"]) : ExtractionRun.where(status: "complete").order(:id).last
    snapshot = ENV["SNAPSHOT"] ? CashlineSnapshot.find(ENV["SNAPSHOT"]) : CashlineSnapshot.current
    abort "No complete extraction run found" unless run
    abort "No cashline snapshot loaded" unless snapshot
    [ run, snapshot ]
  end

  desc "Evaluate the matcher vs the gold set. RUN= SNAPSHOT= MODE=heuristic|proposals (default heuristic)"
  task eval: :environment do
    run, snapshot = resolve_run_and_snapshot
    matcher = ENV["MODE"] == "proposals" ? Mapping::ProposalCandidates.new(snapshot) : Mapping::HeuristicMatcher.new(snapshot: snapshot)

    puts "Matcher eval — run ##{run.id} vs snapshot ##{snapshot.id} — mode=#{ENV['MODE'] || 'heuristic'}"
    puts "=" * 78
    report = Mapping::Evaluator.new(run: run, snapshot: snapshot, matcher: matcher).call

    puts "\nMAPPED objects (does the right target class win?)"
    report[:mapped].each do |r|
      mark = r.hit_at_1 ? "P@1 ✓" : (r.hit_at_k ? "P@3 ~" : "miss ✗")
      ranked = r.ranked.map { |cls, score| "#{cls}(#{score.round(1)})" }.join(", ")
      puts "  [#{mark}] #{r.source_object}"
      puts "         gold: #{r.gold_targets.join(' | ')}"
      puts "         top#{r.ranked.size}: #{ranked}"
    end

    puts "\nNO-TARGET objects (should NOT get a confident home)"
    report[:no_target].each do |r|
      top = r.ranked.first
      flag = (r.top_score.to_f >= Mapping::Evaluator::FALSE_CONFIDENCE) ? "⚠ false-confident" : "ok (low conf)"
      puts "  [#{flag}] #{r.source_object} → #{top ? "#{top.first}(#{top.last.round(2)})" : '(none)'}"
    end

    puts "\n" + "=" * 78
    puts "precision@1:          #{report[:precision_at_1]}"
    puts "recall@3:             #{report[:recall_at_k]}"
    puts "false-confident gaps: #{report[:false_confident_gaps]}/#{report[:no_target].size}"
  end

  desc "Field-level precision@1/recall@3: heuristic vs embedding vs LLM on the field gold set. RUN= SNAPSHOT="
  task field_eval: :environment do
    run, snapshot = resolve_run_and_snapshot
    hm = Mapping::HeuristicMatcher.new(snapshot: snapshot)
    pc = Mapping::ProposalCandidates.new(snapshot)
    llm_on = Anthropic::ClientFactory.configured?

    resolved = Mapping::GoldSet.new.field_pairs.filter_map do |p|
      sf = Sfield.joins(:sobject).find_by(sobjects: { extraction_run_id: run.id, api_name: p.source_object }, api_name: p.source_field)
      sf && [ p, sf ]
    end
    fields = resolved.map(&:last)

    topk = ->(cands, k = 3) { cands.first(k).map { |c| "#{c[:target_class]}.#{c[:target_field]}" } }

    # Heuristic, read directly from the matcher.
    heur = resolved.to_h { |_, sf| [ sf.id, topk.call(hm.candidates_for(sf)) ] }

    # Embedding: repopulate heuristic proposals for these fields, merge embeddings.
    fields.each do |sf|
      MappingProposal.where(source_field_id: sf.id, cashline_snapshot_id: snapshot.id, state: "open").delete_all
      hm.candidates_for(sf).each do |c|
        next if MappingProposal.exists?(source_field_id: sf.id, cashline_snapshot_id: snapshot.id, target_class: c[:target_class], target_field: c[:target_field])
        MappingProposal.create!(source_field_id: sf.id, cashline_snapshot_id: snapshot.id,
          target_class: c[:target_class], target_field: c[:target_field], score: c[:score], signals: c[:signals], state: "open")
      end
    end
    Mapping::EmbeddingMatcher.new(snapshot: snapshot).combine!(run, fields: fields) if Openai::ClientFactory.configured?
    emb = resolved.to_h { |_, sf| [ sf.id, topk.call(pc.candidates_for(sf)) ] }

    # LLM: adjudicate each field, then re-read.
    llm = {}
    if llm_on
      adj = Mapping::LlmAdjudicator.new(snapshot: snapshot)
      fields.each { |sf| adj.adjudicate(sf) }
      llm = resolved.to_h { |_, sf| [ sf.id, topk.call(pc.candidates_for(sf)) ] }
    end

    hit1 = ->(list, targets) { list.first && targets.include?(list.first) }
    hitk = ->(list, targets) { (list & targets).any? }
    mark = ->(b) { b ? "✓" : "✗" }
    cols = llm_on ? %w[heur embed llm] : %w[heur embed]

    puts "Field-level eval — run ##{run.id} vs snapshot ##{snapshot.id} — #{resolved.size} pairs#{llm_on ? '' : ' (no Anthropic key → LLM skipped)'}"
    puts "=" * 78
    printf("%-48s %-6s %-6s %-6s\n", "source field", *cols)
    tallies = Hash.new(0)
    resolved.each do |p, sf|
      preds = { "heur" => heur[sf.id], "embed" => emb[sf.id], "llm" => llm[sf.id] }
      marks = cols.map do |c|
        h = hit1.call(preds[c], p.targets)
        tallies["#{c}_p1"] += 1 if h
        tallies["#{c}_r3"] += 1 if hitk.call(preds[c], p.targets)
        mark.call(h)
      end
      printf("%-48s %-6s %-6s %-6s\n", "#{p.source_object}.#{p.source_field}".last(48), *marks)
    end

    puts "=" * 78
    n = resolved.size
    puts "precision@1:  " + cols.map { |c| "#{c}=#{(tallies["#{c}_p1"].to_f / n).round(2)}" }.join("  ")
    puts "recall@3:     " + cols.map { |c| "#{c}=#{(tallies["#{c}_r3"].to_f / n).round(2)}" }.join("  ")
  end

  desc "Retrieve (heuristic) then LLM-rerank proposals. RUN= SNAPSHOT= OBJECTS=a,b FIELD_LIMIT=n (default: gold objects, all fields)"
  task adjudicate: :environment do
    run, snapshot = resolve_run_and_snapshot
    matcher = Mapping::HeuristicMatcher.new(snapshot: snapshot)
    adjudicator = Mapping::LlmAdjudicator.new(snapshot: snapshot)
    abort "Anthropic not configured — run `bin/rails credentials:edit` and add anthropic.api_key" unless adjudicator.available?

    names = ENV["OBJECTS"].present? ? ENV["OBJECTS"].split(",").map(&:strip) : Mapping::GoldSet.new.source_objects
    field_limit = ENV["FIELD_LIMIT"].to_i

    fields = names.flat_map do |name|
      obj = run.sobjects.find_by(api_name: name)
      next [] unless obj
      scope = obj.sfields.order(:api_name).includes(:spicklist_values)
      (field_limit > 0 ? scope.limit(field_limit) : scope).to_a
    end

    puts "Adjudicating #{fields.size} fields across #{names.size} objects — ~#{fields.size} LLM calls (model: #{Anthropic::Messages::DEFAULT_MODEL})"
    puts "=" * 78

    # Stage 1 — retrieval: (re)populate this field's open heuristic proposals.
    fields.each do |sf|
      MappingProposal.where(source_field_id: sf.id, cashline_snapshot_id: snapshot.id, state: "open").delete_all
      matcher.candidates_for(sf).each do |c|
        next if MappingProposal.rejected?(source_field_id: sf.id, target_class: c[:target_class], target_field: c[:target_field])
        next if MappingProposal.exists?(source_field_id: sf.id, cashline_snapshot_id: snapshot.id, target_class: c[:target_class], target_field: c[:target_field])
        MappingProposal.create!(source_field_id: sf.id, cashline_snapshot_id: snapshot.id,
          target_class: c[:target_class], target_field: c[:target_field], score: c[:score], signals: c[:signals], state: "open")
      end
    end

    # Stage 1b — embedding signal (retrieval enrichment) before the LLM rerank.
    Mapping::EmbeddingMatcher.new(snapshot: snapshot).combine!(run, fields: fields) if Openai::ClientFactory.configured?

    # Stage 2 — rerank + assess: LLM picks the target and writes a role note + disposition.
    done = 0
    fields.each_with_index do |sf, i|
      adjudicator.adjudicate(sf) && (done += 1)
      print(i % 50 == 49 ? "#{i + 1}\n" : ".")
    rescue Anthropic::Error, Faraday::Error => e
      run.record_partial_failure!(object_api_name: "adjudicate:#{sf.api_name}", reason: e.message)
      print "x"
    end
    puts "\nadjudicated #{done}/#{fields.size} fields."

    # Stage 3 — disambiguation: one winner per contested cashline target.
    contested = Mapping::LlmDisambiguator.new(snapshot: snapshot).resolve!(run)
    puts "disambiguated #{contested} contested target(s). Re-run `bin/rails mapping:eval MODE=proposals` to measure lift."
  end
end
