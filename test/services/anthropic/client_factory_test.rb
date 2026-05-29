require "test_helper"

module Anthropic
  class ClientFactoryTest < ActiveSupport::TestCase
    teardown { ClientFactory.credentials = nil }

    test "configured? is false and validate_credentials! raises without an api_key" do
      ClientFactory.credentials = {}
      assert_not ClientFactory.configured?
      assert_raises(Anthropic::ConfigurationError) { ClientFactory.connection }
    end

    test "connection sets the api key and version headers when configured" do
      ClientFactory.credentials = { api_key: "sk-ant-test" }
      assert ClientFactory.configured?
      conn = ClientFactory.connection
      assert_equal "sk-ant-test", conn.headers["x-api-key"]
      assert_equal ClientFactory::API_VERSION, conn.headers["anthropic-version"]
    end
  end
end
