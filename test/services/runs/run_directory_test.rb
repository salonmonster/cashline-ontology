require "test_helper"
require "fileutils"

module Runs
  class RunDirectoryTest < ActiveSupport::TestCase
    setup do
      @tmp_root = Rails.root.join("tmp", "test", "runs", SecureRandom.hex(4))
      FileUtils.mkdir_p(@tmp_root.join("sensitive"))
      File.chmod(0o700, @tmp_root.join("sensitive"))
      RunDirectory.singleton_class.send(:define_method, :default_root) { @test_root }
      RunDirectory.instance_variable_set(:@test_root, @tmp_root)
    end

    teardown do
      RunDirectory.singleton_class.send(:remove_method, :default_root)
      FileUtils.rm_rf(@tmp_root)
    end

    test "non-sensitive run resolves under storage/runs/<token>" do
      run = ExtractionRun.create!(api_version: "62.0", seed_objects: [])
      rd = RunDirectory.for(run)
      assert_equal @tmp_root.join(run.directory_token).to_s, rd.root.to_s
      refute rd.sensitive?
    end

    test "sensitive run resolves under storage/runs/sensitive/<token>" do
      run = ExtractionRun.create!(api_version: "62.0", include_sensitive: true, seed_objects: [])
      rd = RunDirectory.for(run)
      assert_equal @tmp_root.join("sensitive", run.directory_token).to_s, rd.root.to_s
      assert rd.sensitive?
    end

    test "ensure! creates the directory and chmod 700 when sensitive" do
      run = ExtractionRun.create!(api_version: "62.0", include_sensitive: true, seed_objects: [])
      rd = RunDirectory.for(run)
      path = rd.ensure!
      assert File.directory?(path)
      mode = File.stat(path).mode & 0o777
      assert_equal 0o700, mode
    end

    test "write_manifest! produces a readable JSON file" do
      run = ExtractionRun.create!(api_version: "62.0", seed_objects: %w[Account])
      rd = RunDirectory.for(run)
      rd.write_manifest!({ "started_at" => Time.current.iso8601, "objects_visited" => %w[Account] })

      data = JSON.parse(File.read(rd.manifest_path))
      assert_equal %w[Account], data["objects_visited"]
    end

    test "append_jsonl! adds line-delimited JSON records" do
      run = ExtractionRun.create!(api_version: "62.0", seed_objects: %w[Account])
      rd = RunDirectory.for(run)
      path = rd.object_jsonl_path("Account")
      rd.append_jsonl!(path, { record_type: "describe", name: "Account" })
      rd.append_jsonl!(path, { record_type: "tooling_field_metadata", field: "Foo__c" })

      lines = File.readlines(path)
      assert_equal 2, lines.size
      assert_equal "Account", JSON.parse(lines[0])["name"]
      assert_equal "Foo__c", JSON.parse(lines[1])["field"]
    end

    test "object_jsonl_path sanitizes object api names" do
      run = ExtractionRun.create!(api_version: "62.0", seed_objects: [])
      rd = RunDirectory.for(run)
      # Slashes and exotic chars should be replaced; period and underscore preserved.
      path = rd.object_jsonl_path("Foo/Bar__c.weird")
      assert_match(/Foo_Bar__c\.weird\.jsonl\z/, path.to_s)
    end

    test "purge! removes the directory tree" do
      run = ExtractionRun.create!(api_version: "62.0", seed_objects: [])
      rd = RunDirectory.for(run)
      rd.ensure!
      rd.append_jsonl!(rd.object_jsonl_path("Account"), { x: 1 })
      assert File.exist?(rd.root)

      rd.purge!
      refute File.exist?(rd.root)
    end

    test "boot_check! raises when sensitive root is world-readable" do
      insecure_root = @tmp_root.join("insecure")
      FileUtils.mkdir_p(insecure_root.join("sensitive"))
      File.chmod(0o755, insecure_root.join("sensitive"))

      assert_raises(RunDirectory::InsecureSensitiveDirectory) do
        RunDirectory.boot_check!(root: insecure_root)
      end
    end

    test "boot_check! passes when sensitive root is 0700" do
      secure_root = @tmp_root.join("secure")
      FileUtils.mkdir_p(secure_root.join("sensitive"))
      File.chmod(0o700, secure_root.join("sensitive"))

      assert_nothing_raised { RunDirectory.boot_check!(root: secure_root) }
    end

    test "boot_check! is a no-op when sensitive root does not yet exist" do
      assert_nothing_raised { RunDirectory.boot_check!(root: Pathname.new("/nonexistent/path")) }
    end
  end
end
