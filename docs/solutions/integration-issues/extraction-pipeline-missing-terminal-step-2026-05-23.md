---
title: Multi-job pipeline shipped 21 of 21 units, all 178 tests passed, but the terminal step was never wired
date: 2026-05-23
category: integration-issues
module: salesforce_extraction
problem_type: integration_issue
component: background_job
symptoms:
  - Run status permanently stuck at "extracting" after the job chain completes
  - sobjects/sfields/profile tables never populated after a real extraction
  - All 178 isolated unit tests pass with 457 assertions, 0 failures — no test failure signal
  - Demo seeder hides the gap by constructing terminal-state runs directly
  - Plan/README tracking shows "21 of 21 implementation units shipped"
root_cause: missing_workflow_step
resolution_type: code_fix
severity: critical
rails_version: 8.1.0
related_components:
  - service_object
  - testing_framework
tags:
  - background-jobs
  - extraction-pipeline
  - salesforce
  - integration
  - missing-wiring
  - job-chain
  - relational-loader
  - end-to-end-testing
---

# Multi-job pipeline shipped 21 of 21 units, all 178 tests passed, but the terminal step was never wired

## Problem

All 21 implementation units of a Rails 8 multi-job extraction pipeline shipped and passed 178 unit tests, but the terminal step of the pipeline — calling `Runs::RelationalLoader.load!`, fanning out `ProfileObjectJob`, and invoking `run.mark_complete!` — was never wired into `ExtractToolingJob#perform`. Every unit tested only its own state transitions in isolation; no test ever asserted the union of state changes that defines a completed run.

## Symptoms

- A real Salesforce extraction would write JSONL to `storage/runs/<token>/` then leave `ExtractionRun#status` stuck at `"extracting"` forever, because `ExtractToolingJob` ended after the tooling fetch loop with no outbound call.
- The `sobjects`, `sfields`, `srelationships`, and `spicklist_values` tables would remain empty after every live extraction — `RelationalLoader.load!` was only reachable via `lib/tasks/runs.rake` and test files.
- The UI would render as if no run had ever completed: `ActiveRun#current_run` only returns runs with status `complete` or `complete_with_warnings`, so the entire run panel would show nothing.
- `bin/rails test` reported 178 passing, 457 assertions, 0 failures — giving no signal that anything was wrong.
- The README tracked "21 of 21 implementation units shipped" and the demo UI walkthrough rendered correctly, because both paths bypassed the real pipeline entirely.

## What Didn't Work

**Isolated unit tests gave false confidence.** Each job tested only its own postconditions:

- `test/jobs/extract_describe_job_test.rb` asserted JSONL files were written and `ExtractToolingJob` was enqueued — it never checked that `Sobject` rows appeared in the DB.
- `test/jobs/extract_tooling_job_test.rb` (pre-fix) asserted that tooling records were appended to each JSONL and that partial failures were recorded — it never checked `run.status` or `run.sobjects.count` after `perform`.
- `test/services/runs/relational_loader_test.rb` created its own fixture run, called `.load!` directly, and asserted rows existed — but this standalone call never verified that anything in the job chain would ever invoke `.load!`.
- `test/models/extraction_run_test.rb` tested `mark_complete!` in isolation and confirmed the status transition — it proved the method works, not that anything called it.

**The demo seeder masked the gap.** `lib/tasks/demo.rake` constructs `ExtractionRun` records with `status: "complete"` directly and calls `Sobject.create!`, `Sfield.create!`, and `ObjectProfile.create!` inline — bypassing the entire pipeline. Every developer walkthrough of the UI hit the seeder's terminal-state data, never the real job chain. The plan's own status tracking ("21 of 21 shipped") reflected unit completion, not pipeline integration.

**How the bug was caught.** A multi-agent code review (`/ce-code-review`) ran a dedicated correctness persona that traced the full job chain: `ExtractDescribeJob` chains to `ExtractToolingJob`, but `ExtractToolingJob` had no outbound chain and no `mark_complete!` call. The finding was filed with confidence 0.97: *"grep for mark_complete across all app/jobs returns zero hits. RelationalLoader is only invoked by lib/tasks/runs.rake and test files."* The testing persona filed the same gap independently: *"No test for the full job chain verifying that run.status transitions to 'complete' and sobjects/sfields are populated in the DB."* Four reviewers (correctness, maintainability, reliability, testing) converged on the same gap from different angles — cross-reviewer agreement is itself a strong signal.

## Solution

**Pipeline finalization wired into `app/jobs/extract_tooling_job.rb` (commit `a1bbc63`):**

Before — `ExtractToolingJob#perform` ended after the tooling fetch loop:

```ruby
def perform(extraction_run_id)
  run = ExtractionRun.find(extraction_run_id)
  rd = Runs::RunDirectory.for(run)
  fetcher = build_fetcher
  visited_objects(rd).each do |api_name|
    begin
      records = fetcher.fetch_for(api_name)
      records.each { |record| rd.append_jsonl!(rd.object_jsonl_path(api_name), record) }
    rescue Salesforce::Error => e
      run.record_partial_failure!(object_api_name: api_name, reason: "tooling: #{e.message}")
    end
  end
rescue Salesforce::Error => e
  run&.mark_failed!(e.message)
  raise
end
```

After — terminal step wired in:

```ruby
def perform(extraction_run_id)
  run = ExtractionRun.find(extraction_run_id)
  rd = Runs::RunDirectory.for(run)
  fetcher = build_fetcher
  visited_objects(rd).each do |api_name|
    # ... unchanged tooling fetch loop ...
  end

  # Pipeline finalization: load JSONL into relational tables, fan out
  # per-object profiling jobs, stamp a content_hash from the directory
  # contents, and mark the run complete.
  Runs::RelationalLoader.load!(run)
  run.sobjects.pluck(:id).each { |sobject_id| ProfileObjectJob.perform_later(sobject_id) }
  run.mark_complete!(content_hash: rd.content_digest)
rescue Salesforce::Error, ActiveRecord::ActiveRecordError, IOError, SystemCallError => e
  run&.mark_failed!(e.message)
  raise
end
```

**`RunDirectory#content_digest` in `app/services/runs/run_directory.rb`** produces a deterministic SHA256 of the run directory contents. It sorts all `.jsonl` files, hashes each with `Digest::SHA256.file`, appends a corresponding entry for `_manifest.json` if it exists, and runs a final `Digest::SHA256.hexdigest` over the newline-joined `basename:size:sha` strings. Returns `nil` if the directory is absent or empty. This is what `run.mark_complete!(content_hash: rd.content_digest)` passes to stamp the run record.

**Integration test added to `test/jobs/extract_tooling_job_test.rb`:**

```ruby
test "finalizes the run: loads relational tables, fans out profile jobs, stamps content_hash, marks complete" do
  fixed = FixedFetcher.new([{ "record_type" => "tooling_field_metadata", "field_developer_name" => "X" }])
  job = ExtractToolingJob.new
  job.define_singleton_method(:build_fetcher) { fixed }

  assert_enqueued_jobs 2, only: ProfileObjectJob do
    job.perform(@run.id)
  end

  @run.reload
  assert_equal "complete", @run.status
  assert_equal 2, @run.sobjects.count
  assert @run.content_hash.present?
  assert_match(/\A[a-f0-9]{64}\z/, @run.content_hash)
end
```

The test setup pre-seeds two JSONL files (`Account.jsonl`, `Contact.jsonl`) with `describe` records so `RelationalLoader.load!` has real JSONL to parse — matching what the real pipeline writes before `ExtractToolingJob` runs.

## Why This Works

The root cause is a multi-job pipeline where:

1. Each job's unit test asserts only the state changes that job is directly responsible for.
2. No test asserts the union of state changes that defines the terminal state: `run.status == "complete"` AND `run.sobjects.exists?` AND `ProfileObjectJob` enqueued.
3. Because those assertions never existed, the missing wiring between the last real-work step and the terminal step was invisible to the entire test suite.

The fix works because wiring `Runs::RelationalLoader.load!`, `ProfileObjectJob.perform_later`, and `run.mark_complete!` directly into `ExtractToolingJob#perform` makes `ExtractToolingJob` own the pipeline's terminal step. Now there is a single point of truth: when `perform` returns successfully, the run is complete, the DB is populated, and downstream jobs are queued. The integration test enforces this contract by calling `job.perform(@run.id)` and then asserting all three postconditions simultaneously — making any future regression in the terminal step immediately visible.

## Prevention

**1. For any multi-job pipeline: write an integration test that asserts the FINAL state, not just the handoff.**

The pattern to copy — drop into `test/jobs/` for any pipeline-entry job:

```ruby
test "pipeline reaches terminal state" do
  assert_enqueued_jobs N, only: DownstreamJob do
    job.perform(@trigger_input)
  end
  @subject.reload
  assert_equal "complete", @subject.status
  assert @subject.sobjects.exists?
  assert @subject.content_hash.present?
end
```

This pattern depends on `ActiveJob::TestCase` (which sets `queue_adapter_for_test :test` automatically). If you write the same assertion in a model test inheriting `ActiveSupport::TestCase`, set the test adapter explicitly or `assert_enqueued_jobs` will silently see zero.

Apply this to every pipeline-entry job, not just the terminal one. `test/jobs/extract_describe_job_test.rb` currently asserts files were written and `ExtractToolingJob` was enqueued, but it never asserts that a completed run exists when the full chain settles — that's still a gap worth closing if the full chain becomes inline-runnable.

**2. Demo seeders that construct terminal-state objects directly can mask pipeline gaps.**

`lib/tasks/demo.rake`'s `DemoSeeder#build_run` passes `status: "complete"` directly and calls `Sobject.create!` inline, entirely bypassing the job pipeline. This is appropriate for demo purposes (fast UI walkthrough without external dependencies), but the gap it creates is exactly what happened here: every developer walkthrough proved the UI works, not that the pipeline produces what the UI reads. **If your demo seeder constructs terminal-state objects directly, you must have a pipeline integration test that is independent of the seeder.**

**3. Per-unit verification fields (test count, plan-unit checkboxes) are necessary but not sufficient.**

The plan tracked "21 of 21 implementation units shipped" and "178 tests passing." Both were accurate. **Unit completeness does not imply integration correctness:** each unit can pass while their composition fails silently. Count-based progress tracking is useful for planning; it should not substitute for an end-to-end assertion that the composed system reaches its intended terminal state.

**4. Grep for terminal-state calls at pipeline boundaries before marking a pipeline complete.**

Before the fix, `grep -r "mark_complete" app/jobs/` returned zero hits. This is the simplest possible signal that something is missing in a stateful pipeline. A lightweight review heuristic: for any pipeline that has a "complete" terminal state, at least one job must call `mark_complete!` (or equivalent), and at least one test must assert that status from outside the job.

**5. A fixture-based full-chain integration test covering `ExtractDescribeJob` through `run.status == "complete"` is the remaining gap; the override seams (`build_fetcher` via `define_singleton_method`, `Salesforce::ClientFactory.rest` via `instance_variable_set`) already exist.**

## Trade-offs and known limitations

Two caveats about the fix as shipped:

- **Job thickness.** Wiring the three-step finalization (`load!` + fan-out + `mark_complete!`) directly into `ExtractToolingJob#perform` makes the job own pipeline orchestration. A more model-centric alternative is `ExtractionRun#complete_extraction!` — the model already owns `mark_complete!`, `mark_failed!`, and `record_partial_failure!`. With the orchestration on the model, a rake task or controller action can trigger completion without re-implementing the three steps. The trade-off is a slightly larger model; we accepted the thicker job to keep the fix surgical, but anyone copying this pattern should consider model placement.
- **`.new + .perform` vs the adapter.** The integration test instantiates `ExtractToolingJob.new` and calls `.perform` directly to inject a fake fetcher via `define_singleton_method`. This bypasses `ActiveJob`'s `before_perform`/`after_perform`/`retry_on`/`discard_on` machinery. `ApplicationJob` has no such callbacks today, so the bypass is fine — but if you add adapter-layer behavior later, switch to `perform_later` + `perform_enqueued_jobs` so the test exercises it.

## Related Issues

- Commit `a1bbc63` — the pipeline wiring fix and integration test
- Multi-agent code review run: `.context/compound-engineering/ce-code-review/20260523-210204-f9fe74c1/` (correctness.json, maintainability.json, reliability.json, testing.json — all four independently flagged this from different angles, demonstrating cross-reviewer agreement as a strong signal)
- Originating plan: `docs/plans/2026-05-23-001-feat-sailfin-extraction-and-phase-1-ui-plan.md` (Unit 11 RelationalLoader, Unit 13 ProfileObjectJob — both implemented and tested in isolation, never wired into the chain)
