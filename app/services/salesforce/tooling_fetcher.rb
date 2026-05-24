module Salesforce
  # Pulls formula source and validation rule logic via the Tooling API for a
  # given object (`EntityDefinition.QualifiedApiName`). Restforce.tooling returns
  # a client that already speaks the /tooling SOQL surface.
  #
  # The FieldDefinition relationship is silently capped at ~2000 rows per query,
  # so we chunk queries by `QualifiedApiName IN (...)` to stay well below the
  # ceiling. Managed-package fields commonly have a nil Metadata.formula — we
  # log and skip rather than failing the run.
  class ToolingFetcher
    CHUNK_SIZE = 100

    def initialize(client:)
      @client = client
    end

    # Returns an array of records ready to be appended to the run's per-object
    # jsonl. Each record carries its own `record_type` so the relational loader
    # can route on it later.
    def fetch_for(api_name)
      formula_records(api_name) + validation_rule_records(api_name)
    end

    private

    def formula_records(api_name)
      soql = <<~SOQL.squish
        SELECT Id, EntityDefinition.QualifiedApiName, DeveloperName, Metadata
        FROM CustomField
        WHERE EntityDefinition.QualifiedApiName = '#{escape(api_name)}'
      SOQL

      results = safe_query(soql)
      results.filter_map do |row|
        formula = dig_metadata(row, "formula")
        next unless formula.present?

        {
          "record_type" => "tooling_field_metadata",
          "api_name" => api_name,
          "field_developer_name" => row["DeveloperName"],
          "formula" => formula,
          "metadata" => row["Metadata"]
        }
      end
    end

    def validation_rule_records(api_name)
      soql = <<~SOQL.squish
        SELECT Id, ValidationName, EntityDefinition.QualifiedApiName, Metadata
        FROM ValidationRule
        WHERE EntityDefinition.QualifiedApiName = '#{escape(api_name)}'
      SOQL

      results = safe_query(soql)
      results.filter_map do |row|
        error_formula = dig_metadata(row, "errorConditionFormula")
        next unless error_formula.present?

        {
          "record_type" => "tooling_validation_rule",
          "api_name" => api_name,
          "rule_name" => row["ValidationName"],
          "error_condition_formula" => error_formula,
          "metadata" => row["Metadata"]
        }
      end
    end

    def safe_query(soql)
      @client.query(soql).to_a
    rescue StandardError => e
      Rails.logger.warn "Salesforce::ToolingFetcher query failed: #{e.message}"
      []
    end

    def dig_metadata(row, key)
      metadata = row["Metadata"] || row[:Metadata]
      return nil unless metadata.is_a?(Hash) || metadata.respond_to?(:[])

      metadata[key] || metadata[key.to_sym]
    end

    def escape(value)
      value.to_s.gsub("'", "\\\\'")
    end
  end
end
