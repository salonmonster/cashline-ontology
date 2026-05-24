require "test_helper"
require "fileutils"

class ExtractToolingJobTest < ActiveJob::TestCase
  class FixedFetcher
    def initialize(records)
      @records = records
    end

    def fetch_for(api_name)
      @records.map { |r| r.merge("api_name" => api_name) }
    end
  end

  class RaisingFetcher
    def fetch_for(_api_name)
      raise Salesforce::Error, "tooling failure"
    end
  end

  setup do
    @tmp_root = Rails.root.join("tmp", "test", "extract_tooling_job", SecureRandom.hex(4))
    FileUtils.mkdir_p(@tmp_root)
    Runs::RunDirectory.singleton_class.send(:define_method, :default_root) { @test_root }
    Runs::RunDirectory.instance_variable_set(:@test_root, @tmp_root)

    @run = ExtractionRun.create!(api_version: "62.0", seed_objects: %w[Account])
    rd = Runs::RunDirectory.for(@run)
    rd.ensure!
    rd.write_manifest!(
      "extraction_run_id" => @run.id,
      "objects_visited" => %w[Account Contact]
    )
    rd.append_jsonl!(rd.object_jsonl_path("Account"), { record_type: "describe", api_name: "Account" })
    rd.append_jsonl!(rd.object_jsonl_path("Contact"), { record_type: "describe", api_name: "Contact" })
  end

  teardown do
    Runs::RunDirectory.singleton_class.send(:remove_method, :default_root)
    FileUtils.rm_rf(@tmp_root)
  end

  test "appends tooling records to each visited object's jsonl" do
    fixed = FixedFetcher.new([{ "record_type" => "tooling_field_metadata", "field_developer_name" => "X" }])

    job = ExtractToolingJob.new
    job.define_singleton_method(:build_fetcher) { fixed }
    job.perform(@run.id)

    rd = Runs::RunDirectory.for(@run.reload)
    %w[Account Contact].each do |obj|
      records = File.readlines(rd.object_jsonl_path(obj)).map { |l| JSON.parse(l) }
      assert records.any? { |r| r["record_type"] == "tooling_field_metadata" }, "expected tooling record for #{obj}"
    end
  end

  test "records a partial failure when fetcher raises Salesforce::Error" do
    raising = RaisingFetcher.new

    job = ExtractToolingJob.new
    job.define_singleton_method(:build_fetcher) { raising }
    job.perform(@run.id)

    @run.reload
    assert_equal 2, @run.partial_failures.size
    assert_includes @run.partial_failures.map { |pf| pf["object_api_name"] }, "Account"
  end
end
