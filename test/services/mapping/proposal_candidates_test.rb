require "test_helper"

module Mapping
  class ProposalCandidatesTest < ActiveSupport::TestCase
    setup do
      @run = ExtractionRun.create!(api_version: "62.0", include_sensitive: false)
      @sobject = Sobject.create!(extraction_run: @run, api_name: "Acct", label: "Acct")
      @sfield = Sfield.create!(sobject: @sobject, api_name: "F__c")
      @snapshot = CashlineSnapshot.create!(loaded_at: Time.current, sha256: "s", schema_json: {})
    end

    def proposal(field, score:, state:)
      MappingProposal.create!(source_field: @sfield, cashline_snapshot: @snapshot,
        target_class: "Invoice", target_field: field, score: score, state: state, signals: {})
    end

    test "returns open and accepted proposals ordered by score desc, excluding rejected" do
      proposal("low", score: 0.5, state: "open")
      proposal("high", score: 0.9, state: "accepted")
      proposal("nope", score: 0.7, state: "rejected")

      cands = ProposalCandidates.new(@snapshot).candidates_for(@sfield)

      assert_equal %w[high low], cands.map { |c| c[:target_field] }
      assert_equal "Invoice", cands.first[:target_class]
      assert cands.first.key?(:score) && cands.first.key?(:signals)
    end
  end
end
