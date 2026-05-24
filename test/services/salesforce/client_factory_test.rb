require "test_helper"

module Salesforce
  class ClientFactoryTest < ActiveSupport::TestCase
    setup do
      Rails.cache.clear
      @fake_creds = {
        consumer_key: "test-consumer-key",
        username: "integration@example.com",
        instance_url: "https://example.my.salesforce.com",
        sandbox: true,
        private_key: "(test-key)"
      }
      ClientFactory.singleton_class.send(:define_method, :credentials) { @test_creds }
      ClientFactory.instance_variable_set(:@test_creds, @fake_creds)
    end

    teardown do
      ClientFactory.singleton_class.send(:remove_method, :credentials)
    end

    test "ensure_token caches the result of the JWT exchange block" do
      call_count = 0
      ClientFactory.singleton_class.send(:define_method, :perform_jwt_exchange) do
        call_count += 1
        TokenCache::Token.new(
          access_token: "fresh-token",
          instance_url: "https://x.salesforce.com",
          fetched_at: Time.current
        )
      end

      t1 = ClientFactory.ensure_token
      t2 = ClientFactory.ensure_token

      assert_equal "fresh-token", t1.access_token
      assert_equal t1.access_token, t2.access_token
      assert_equal 1, call_count, "second ensure_token call should reuse cached token"
    ensure
      ClientFactory.singleton_class.send(:remove_method, :perform_jwt_exchange)
    end

    test "invalidate_token! forces the next ensure_token to re-exchange" do
      call_count = 0
      ClientFactory.singleton_class.send(:define_method, :perform_jwt_exchange) do
        call_count += 1
        TokenCache::Token.new(
          access_token: "token-#{call_count}",
          instance_url: "https://x.salesforce.com",
          fetched_at: Time.current
        )
      end

      ClientFactory.ensure_token
      ClientFactory.invalidate_token!
      ClientFactory.ensure_token

      assert_equal 2, call_count
    ensure
      ClientFactory.singleton_class.send(:remove_method, :perform_jwt_exchange)
    end

    test "ensure_token(force: true) bypasses the cache" do
      call_count = 0
      ClientFactory.singleton_class.send(:define_method, :perform_jwt_exchange) do
        call_count += 1
        TokenCache::Token.new(
          access_token: "token-#{call_count}",
          instance_url: "https://x.salesforce.com",
          fetched_at: Time.current
        )
      end

      ClientFactory.ensure_token
      ClientFactory.ensure_token(force: true)

      assert_equal 2, call_count
    ensure
      ClientFactory.singleton_class.send(:remove_method, :perform_jwt_exchange)
    end
  end
end
