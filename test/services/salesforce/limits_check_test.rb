require "test_helper"
require "ostruct"

module Salesforce
  class LimitsCheckTest < ActiveSupport::TestCase
    # A minimal stand-in for the Restforce client surface LimitsCheck uses.
    # Holds whatever body we want the next .get("limits") to return.
    class StubClient
      attr_writer :limits_body
      def get(path)
        raise "unexpected path #{path}" unless path == "limits"
        OpenStruct.new(body: @limits_body)
      end
    end

    setup do
      @client = StubClient.new
    end

    test "call returns only interesting limits with Max/Remaining" do
      @client.limits_body = {
        "DailyApiRequests" => { "Max" => 15_000, "Remaining" => 14_000 },
        "DailyBulkApiBatches" => { "Max" => 15_000, "Remaining" => 14_999 },
        "DailyBulkV2QueryJobs" => { "Max" => 10_000, "Remaining" => 9_500 },
        "ConcurrentAsyncGetReportInstances" => { "Max" => 200, "Remaining" => 199 },
        "PermissionSets" => { "Max" => 1500, "Remaining" => 1490 } # ignored
      }
      result = LimitsCheck.call(@client)

      assert_equal 4, result.size
      assert_equal 14_000, result["DailyApiRequests"]["Remaining"]
      refute result.key?("PermissionSets")
    end

    test "guard! returns snapshot when over threshold" do
      @client.limits_body = {
        "DailyApiRequests" => { "Max" => 15_000, "Remaining" => 14_000 }, # 93%
        "DailyBulkApiBatches" => { "Max" => 15_000, "Remaining" => 14_999 },
        "DailyBulkV2QueryJobs" => { "Max" => 10_000, "Remaining" => 9_500 },
        "ConcurrentAsyncGetReportInstances" => { "Max" => 200, "Remaining" => 199 }
      }

      assert_nothing_raised { LimitsCheck.guard!(@client) }
    end

    test "guard! raises when any limit is below the percent threshold" do
      @client.limits_body = {
        "DailyApiRequests" => { "Max" => 15_000, "Remaining" => 1_000 }, # 6.6%
        "DailyBulkApiBatches" => { "Max" => 15_000, "Remaining" => 14_999 },
        "DailyBulkV2QueryJobs" => { "Max" => 10_000, "Remaining" => 9_500 },
        "ConcurrentAsyncGetReportInstances" => { "Max" => 200, "Remaining" => 199 }
      }
      e = assert_raises(Salesforce::QuotaExhausted) { LimitsCheck.guard!(@client) }
      assert_match(/DailyApiRequests/, e.message)
    end

    test "guard! raises when absolute remaining is below raise_below floor" do
      @client.limits_body = {
        "DailyApiRequests" => { "Max" => 15_000, "Remaining" => 14_000 },
        "DailyBulkApiBatches" => { "Max" => 15_000, "Remaining" => 14_999 },
        # 100% but only 3 remaining absolute — below raise_below: 5
        "DailyBulkV2QueryJobs" => { "Max" => 3, "Remaining" => 3 },
        "ConcurrentAsyncGetReportInstances" => { "Max" => 200, "Remaining" => 199 }
      }
      e = assert_raises(Salesforce::QuotaExhausted) { LimitsCheck.guard!(@client) }
      assert_match(/DailyBulkV2QueryJobs/, e.message)
    end

    test "guard! ignores limits where Max is zero" do
      @client.limits_body = {
        "DailyApiRequests" => { "Max" => 15_000, "Remaining" => 14_000 },
        "DailyBulkApiBatches" => { "Max" => 0, "Remaining" => 0 }, # not a real limit
        "DailyBulkV2QueryJobs" => { "Max" => 10_000, "Remaining" => 9_500 },
        "ConcurrentAsyncGetReportInstances" => { "Max" => 200, "Remaining" => 199 }
      }
      e = assert_raises(Salesforce::QuotaExhausted) { LimitsCheck.guard!(@client) }
      # DailyBulkApiBatches has Remaining=0 which triggers the raise_below floor
      assert_match(/DailyBulkApiBatches/, e.message)
    end
  end
end
