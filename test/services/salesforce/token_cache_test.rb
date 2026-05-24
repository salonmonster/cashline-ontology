require "test_helper"

module Salesforce
  class TokenCacheTest < ActiveSupport::TestCase
    setup do
      Rails.cache.clear
      @consumer_key = "test-consumer-key"
    end

    test "cache key is stable across calls for the same consumer + env" do
      k1 = TokenCache.cache_key(consumer_key: @consumer_key, sandbox: true)
      k2 = TokenCache.cache_key(consumer_key: @consumer_key, sandbox: true)
      assert_equal k1, k2
    end

    test "cache key differs for sandbox vs production" do
      k_sb = TokenCache.cache_key(consumer_key: @consumer_key, sandbox: true)
      k_prod = TokenCache.cache_key(consumer_key: @consumer_key, sandbox: false)
      refute_equal k_sb, k_prod
    end

    test "cache key differs for different consumer keys" do
      k_a = TokenCache.cache_key(consumer_key: "consumer-a", sandbox: true)
      k_b = TokenCache.cache_key(consumer_key: "consumer-b", sandbox: true)
      refute_equal k_a, k_b
    end

    test "cache key does not embed the raw consumer key" do
      key = TokenCache.cache_key(consumer_key: @consumer_key, sandbox: true)
      refute_includes key, @consumer_key
    end

    test "fetch returns the block's token on cold cache" do
      token = TokenCache::Token.new(
        access_token: "abc",
        instance_url: "https://x.salesforce.com",
        fetched_at: Time.current
      )
      call_count = 0
      result = TokenCache.fetch(consumer_key: @consumer_key, sandbox: true) do
        call_count += 1
        token
      end
      assert_equal token.access_token, result.access_token
      assert_equal 1, call_count
    end

    test "fetch reuses cached token without calling the block again" do
      token = TokenCache::Token.new(
        access_token: "cached",
        instance_url: "https://x.salesforce.com",
        fetched_at: Time.current
      )
      TokenCache.fetch(consumer_key: @consumer_key, sandbox: true) { token }

      call_count = 0
      result = TokenCache.fetch(consumer_key: @consumer_key, sandbox: true) do
        call_count += 1
        TokenCache::Token.new(access_token: "fresh", instance_url: "x", fetched_at: Time.current)
      end
      assert_equal "cached", result.access_token
      assert_equal 0, call_count
    end

    test "fetch re-exchanges when cached token is expired" do
      old_token = TokenCache::Token.new(
        access_token: "old",
        instance_url: "https://x.salesforce.com",
        fetched_at: 3.hours.ago
      )
      TokenCache.fetch(consumer_key: @consumer_key, sandbox: true, lifetime_seconds: 60) { old_token }
      # Simulate the cache reading back the stale entry by writing it directly
      # (the in-process cache may eject already; this guarantees expiry semantics
      # exercise the Token#expired? path).
      Rails.cache.write(
        TokenCache.cache_key(consumer_key: @consumer_key, sandbox: true),
        old_token
      )

      result = TokenCache.fetch(consumer_key: @consumer_key, sandbox: true, lifetime_seconds: 60) do
        TokenCache::Token.new(access_token: "fresh", instance_url: "x", fetched_at: Time.current)
      end
      assert_equal "fresh", result.access_token
    end

    test "invalidate removes the cached entry" do
      token = TokenCache::Token.new(
        access_token: "x",
        instance_url: "x",
        fetched_at: Time.current
      )
      TokenCache.fetch(consumer_key: @consumer_key, sandbox: true) { token }
      TokenCache.invalidate(consumer_key: @consumer_key, sandbox: true)

      assert_nil TokenCache.read(consumer_key: @consumer_key, sandbox: true)
    end

    test "Token#expired? respects the 5-minute safety margin" do
      lifetime = 60.minutes.to_i
      fresh = TokenCache::Token.new(access_token: "x", instance_url: "x", fetched_at: 1.minute.ago)
      almost = TokenCache::Token.new(access_token: "x", instance_url: "x", fetched_at: 56.minutes.ago)
      stale = TokenCache::Token.new(access_token: "x", instance_url: "x", fetched_at: 70.minutes.ago)

      refute fresh.expired?(lifetime_seconds: lifetime)
      assert almost.expired?(lifetime_seconds: lifetime), "token within 5min of expiry should be expired"
      assert stale.expired?(lifetime_seconds: lifetime)
    end
  end
end
