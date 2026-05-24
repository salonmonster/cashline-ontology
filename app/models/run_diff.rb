class RunDiff < ApplicationRecord
  belongs_to :run_a, class_name: "ExtractionRun"
  belongs_to :run_b, class_name: "ExtractionRun"

  validates :computed_at, presence: true
  validates :run_a_id, uniqueness: { scope: :run_b_id }

  CATEGORIES = %w[
    object_added
    object_removed
    field_added
    field_removed
    field_type_changed
    field_length_changed
    picklist_values_added
    picklist_values_removed
    relationship_added
    relationship_removed
    formula_logic_changed
    validation_rule_changed
  ].freeze

  def category(name)
    Array(diff && diff[name.to_s])
  end

  def empty?
    CATEGORIES.all? { |c| category(c).empty? }
  end

  def total_changes
    CATEGORIES.sum { |c| category(c).size }
  end

  def installed_package_changes
    diff && diff["installed_package_changes"] || { "added" => [], "removed" => [], "version_changed" => [] }
  end
end
