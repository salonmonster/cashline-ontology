# Namespace + domain error hierarchy for everything that talks to Salesforce.
module Salesforce
  # Base for all Salesforce-related errors. Catching this in a job covers
  # auth failures, quota exhaustion, and transport errors uniformly.
  class Error < StandardError; end

  # Raised when JWT exchange fails or returns no token.
  class AuthenticationError < Error; end

  # Raised when pre-flight LimitsCheck.guard! says we shouldn't proceed.
  class QuotaExhausted < Error; end

  # The Salesforce REST API version we pin against. Bumping is a deliberate
  # decision — describe payloads differ field-by-field across versions and
  # we don't want diffs polluted by API-version drift.
  API_VERSION = "62.0"
end
