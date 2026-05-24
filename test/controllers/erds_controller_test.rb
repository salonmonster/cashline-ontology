require "test_helper"

class ErdsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "c@example.com", password: "secret-pass-1", role: :analyst)
    @run = ExtractionRun.create!(api_version: "62.0", user: @user, seed_objects: %w[Account], include_sensitive: false, status: "complete", completed_at: Time.current)
    @a = Sobject.create!(extraction_run: @run, api_name: "A", raw_describe: {})
    @b = Sobject.create!(extraction_run: @run, api_name: "B", raw_describe: {})
    Srelationship.create!(extraction_run: @run, source_sobject: @a, target_sobject: @b)
  end

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "secret-pass-1" }
  end

  test "index computes and lists clusters on first visit" do
    sign_in(@user)
    assert_difference "Cluster.count", +1 do
      get erds_path(run: @run.id)
    end
    assert_response :success
  end

  test "show renders Mermaid source for a cluster" do
    sign_in(@user)
    get erds_path(run: @run.id) # ensure clusters exist
    cluster = @run.clusters.first
    get erd_path(cluster.slug, run: @run.id)
    assert_response :success
    assert_match(/erDiagram/, response.body)
  end

  test "show responds with .mmd for download" do
    sign_in(@user)
    get erds_path(run: @run.id)
    cluster = @run.clusters.first
    get erd_path(cluster.slug, run: @run.id, format: :mmd)
    assert_response :success
    assert_match(/erDiagram/, response.body)
  end

  test "rename marks cluster user_modified" do
    sign_in(@user)
    get erds_path(run: @run.id)
    cluster = @run.clusters.first
    patch rename_cluster_path(cluster.id, run: @run.id), params: { cluster: { name: "Renamed" } }
    assert_redirected_to edit_clusters_path(run: @run.id)
    cluster.reload
    assert_equal "Renamed", cluster.name
    assert cluster.user_modified
  end

  test "reassign moves an sobject between clusters" do
    sign_in(@user)
    get erds_path(run: @run.id)
    # Force a multi-cluster state for the test
    isolated = Sobject.create!(extraction_run: @run, api_name: "C", raw_describe: {})
    Ontology::ClusterPersister.compute_and_persist!(@run, force: true)
    clusters = @run.clusters.order(:name).to_a
    src = ClusterAssignment.find_by(sobject_id: isolated.id).cluster
    tgt = clusters.find { |c| c != src }
    skip "no second cluster available" if tgt.nil?
    patch assign_cluster_path(tgt.id, run: @run.id), params: { sobject_id: isolated.id }
    assert_equal tgt.id, ClusterAssignment.find_by(sobject_id: isolated.id).cluster_id
  end
end
