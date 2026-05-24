require "test_helper"

class RunsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @analyst = User.create!(email_address: "analyst@example.com", password: "secret-pass-1", role: :analyst, sensitive_data_access: false)
    @analyst_pii = User.create!(email_address: "pii@example.com", password: "secret-pass-1", role: :analyst, sensitive_data_access: true)
    @reader = User.create!(email_address: "reader@example.com", password: "secret-pass-1", role: :read_only)
  end

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "secret-pass-1" }
  end

  test "analyst sees runs index" do
    sign_in(@analyst)
    get runs_path
    assert_response :success
  end

  test "read_only user cannot reach runs/new" do
    sign_in(@reader)
    get new_run_path
    assert_redirected_to root_path
  end

  test "analyst without sensitive_data_access does not see the include_sensitive toggle" do
    sign_in(@analyst)
    get new_run_path
    assert_response :success
    refute_match(/include[-_]sensitive/, response.body, "should not render PII toggle without role")
  end

  test "analyst with sensitive_data_access sees include_sensitive toggle" do
    sign_in(@analyst_pii)
    get new_run_path
    assert_response :success
    assert_match(/include_sensitive/, response.body)
  end

  test "creating a non-sensitive run enqueues ExtractDescribeJob, audits, and redirects" do
    sign_in(@analyst)
    assert_enqueued_with(job: ExtractDescribeJob) do
      assert_difference "AuditEvent.count", +1 do
        assert_difference "ExtractionRun.count", +1 do
          post runs_path, params: {
            extraction_run: { preset: "ar_default", api_version: "62.0", include_sensitive: false }
          }
        end
      end
    end
    run = ExtractionRun.order(:id).last
    assert_equal "queued", run.status
    assert_equal @analyst.id, run.user_id
    audit = AuditEvent.order(:id).last
    assert_equal "run.trigger", audit.action
    assert_redirected_to run_path(run)
  end

  test "creating a sensitive run requires the role" do
    sign_in(@analyst)
    assert_no_difference "ExtractionRun.count" do
      post runs_path, params: { extraction_run: { preset: "ar_default", include_sensitive: true } }
    end
  end

  test "sensitive run create succeeds with role" do
    sign_in(@analyst_pii)
    assert_difference "ExtractionRun.count", +1 do
      post runs_path, params: { extraction_run: { preset: "ar_default", include_sensitive: true } }
    end
    run = ExtractionRun.order(:id).last
    assert run.include_sensitive
    assert_not_nil run.retained_until
  end

  test "read_only user cannot view a sensitive run's details" do
    run = ExtractionRun.create!(api_version: "62.0", include_sensitive: true, user: @analyst_pii, seed_objects: %w[Account])
    sign_in(@reader)
    get run_path(run)
    assert_redirected_to root_path
  end
end
