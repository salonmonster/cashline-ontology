# The LLM enrichment verdict for one Sailfin field against one cashline snapshot:
# a generated functional-role note plus a keep/need/discard disposition. Distinct
# from MappingProposal (per candidate target) — this is the field-level summary
# that drives the grid's context-notes and disposition columns. Covers every
# field, including ones with no proposal.
class FieldAssessment < ApplicationRecord
  belongs_to :sfield
  belongs_to :cashline_snapshot

  # keep            — exists in both Sailfin and cashline; carry it forward.
  # need_in_cashline — used in Sailfin but no cashline home; add it to cashline.
  # discard         — exists in Sailfin but unused/not useful; drop it.
  DISPOSITIONS = %w[keep need_in_cashline discard].freeze

  validates :disposition, inclusion: { in: DISPOSITIONS }, allow_nil: true

  LABELS = { "keep" => "keep", "need_in_cashline" => "need in cashline", "discard" => "discard" }.freeze

  def disposition_label
    LABELS[disposition] || disposition
  end
end
