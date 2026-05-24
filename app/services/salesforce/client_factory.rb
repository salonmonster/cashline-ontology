require "restforce"

module Salesforce
  # Produces Restforce REST + Tooling clients backed by JWT Bearer auth and
  # a shared token cache. Use ClientFactory.rest / .tooling at the start of
  # each unit of work — never hold a long-lived reference across job
  # boundaries, because the underlying token may change (cert rotation,
  # sandbox refresh, single-flight refresh in another worker).
  module ClientFactory
    extend self

    # Returns a Restforce::Data::Client for REST/SOQL traffic.
    def rest
      Restforce.new(client_config)
    end

    # Returns a Restforce::Tooling::Client for formula source, validation
    # rule logic, EntityDefinition metadata, etc. Restforce 8 exposes this
    # via the top-level `tooling` factory method (verified at plan-review
    # time against restforce/restforce@v8.0.1).
    def tooling
      Restforce.tooling(client_config)
    end

    # Force-invalidates the cached token. Call this when a downstream call
    # returns 401 or 404 (sandbox refresh / instance migration).
    def invalidate_token!
      TokenCache.invalidate(consumer_key: credentials.fetch(:consumer_key), sandbox: sandbox?)
    end

    # @return [Salesforce::TokenCache::Token] a usable, fresh token. Triggers
    #   a JWT exchange if no cached entry exists or the existing one has
    #   expired. Caller may pass `force: true` to skip the cache (used after
    #   401 retry).
    def ensure_token(force: false)
      validate_credentials!
      invalidate_token! if force

      TokenCache.fetch(
        consumer_key: credentials.fetch(:consumer_key),
        sandbox: sandbox?
      ) { perform_jwt_exchange }
    end

    # Surfaces a clear configuration error before the first JWT exchange.
    # Without this, a missing credentials file raises a bare KeyError that
    # bubbles up through job-level rescues with an opaque message.
    def validate_credentials!
      required = %i[consumer_key username instance_url private_key]
      missing = required.reject { |key| credentials[key].to_s.strip.present? }
      return if missing.empty?
      raise Salesforce::AuthenticationError,
            "Salesforce credentials not configured (missing #{missing.join(', ')}). " \
            "Run `bin/rails credentials:edit -e #{Rails.env}` and add the `salesforce:` block " \
            "as documented in docs/runbook/salesforce-connected-app.md."
    end

    private

    # Restforce config shared by REST and Tooling clients. Authentication
    # callback writes any token Restforce mints into our cache so two clients
    # can share creds.
    def client_config
      {
        api_version: API_VERSION,
        username: credentials.fetch(:username),
        client_id: credentials.fetch(:consumer_key),
        instance_url: credentials.fetch(:instance_url),
        host: sandbox? ? "test.salesforce.com" : "login.salesforce.com",
        jwt_key: credentials.fetch(:private_key),
        authentication_callback: ->(auth) {
          token = TokenCache::Token.new(
            access_token: auth.access_token,
            instance_url: auth.instance_url,
            fetched_at: Time.current
          )
          ttl_seconds = (auth.respond_to?(:expires_in) && auth.expires_in) || 2.hours.to_i
          Rails.cache.write(
            TokenCache.cache_key(consumer_key: credentials.fetch(:consumer_key), sandbox: sandbox?),
            token,
            expires_in: ttl_seconds - 5.minutes.to_i,
            race_condition_ttl: 30
          )
        }
      }
    end

    # Forces a JWT exchange and returns a Token. Used when the cache is
    # empty AND we hold the single-flight advisory lock — callers should
    # always go through TokenCache.fetch, not call this directly.
    def perform_jwt_exchange
      client = Restforce.new(client_config)
      auth = client.authenticate!
      TokenCache::Token.new(
        access_token: auth.access_token,
        instance_url: auth.instance_url,
        fetched_at: Time.current
      )
    rescue Restforce::AuthenticationError => e
      raise Salesforce::AuthenticationError, "JWT exchange failed: #{e.message}"
    end

    def credentials
      Rails.application.credentials.salesforce || {}
    end

    def sandbox?
      credentials.fetch(:sandbox, false)
    end
  end
end
