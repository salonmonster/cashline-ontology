module Salesforce
  # Pre-flight check against Salesforce's /services/data/vXX/limits endpoint.
  # Used before extraction or large profiling jobs so we don't kick off work
  # that will fail mid-stream on a quota hit.
  #
  # The endpoint is accurate to ~5 minutes (Salesforce caches it that long)
  # so this is a coarse gate, not a precise budget tracker.
  module LimitsCheck
    extend self

    # Buckets we care about for cashline-ontology workloads.
    INTERESTING_LIMITS = %w[
      DailyApiRequests
      DailyBulkApiBatches
      DailyBulkV2QueryJobs
      ConcurrentAsyncGetReportInstances
    ].freeze

    # @param client [Restforce::Data::Client] usually `Salesforce::ClientFactory.rest`
    # @return [Hash{String => Hash{String => Integer}}] limit name -> {"Max" => , "Remaining" => }
    def call(client)
      raw = client.get("limits").body
      raw
        .slice(*INTERESTING_LIMITS)
        .transform_values { |v| v.to_h.slice("Max", "Remaining") }
    end

    # Raises Salesforce::QuotaExhausted unless every interesting limit has
    # enough headroom to start a new run.
    #
    # @param threshold [Float] required remaining/max ratio (e.g., 0.10 = 10%)
    # @param raise_below [Integer] hard floor on absolute remaining count
    # @raise [Salesforce::QuotaExhausted]
    def guard!(client, threshold: 0.10, raise_below: 5)
      snapshot = call(client)
      starved = snapshot.select do |_name, limit|
        max = limit["Max"].to_i
        remaining = limit["Remaining"].to_i
        next true if remaining < raise_below

        max.positive? && (remaining.to_f / max < threshold)
      end

      return snapshot if starved.empty?

      details = starved.map { |k, v| "#{k}: #{v['Remaining']}/#{v['Max']}" }.join(", ")
      raise Salesforce::QuotaExhausted,
            "Salesforce API quota exhausted or near-exhausted (#{details})"
    end
  end
end
