require "faraday"

module Anthropic
  # Thin Faraday client for the one Anthropic endpoint this app uses (Messages).
  # Modeled on Openai::ClientFactory / Salesforce::ClientFactory — no new gem,
  # credentials in Rails.application.credentials.anthropic. The matcher degrades
  # to heuristic-only when this is not configured.
  module ClientFactory
    extend self

    API_BASE = "https://api.anthropic.com".freeze
    API_VERSION = "2023-06-01".freeze

    def configured?
      credentials[:api_key].to_s.strip.present?
    end

    def validate_credentials!
      return if configured?
      raise ConfigurationError,
            "Anthropic credentials not configured (missing api_key). " \
            "Run `bin/rails credentials:edit` and add:\n  anthropic:\n    api_key: sk-ant-...\n" \
            "LLM adjudication degrades to heuristic-only until this is set."
    end

    def connection
      validate_credentials!
      Faraday.new(url: API_BASE) do |f|
        f.request :json
        f.response :json
        f.headers["x-api-key"] = credentials.fetch(:api_key)
        f.headers["anthropic-version"] = API_VERSION
        f.options.timeout = 120
        f.options.open_timeout = 10
      end
    end

    # Test seam: assign Anthropic::ClientFactory.credentials = {api_key: "..."}
    # (or {}) to override; nil falls back to Rails credentials.
    attr_writer :credentials

    def credentials
      @credentials || Rails.application.credentials.anthropic || {}
    end
  end
end
