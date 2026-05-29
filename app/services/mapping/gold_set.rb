module Mapping
  # Loads the hand-confirmed entity-level gold mappings (config/mapping_gold_set.yml)
  # used by Mapping::Evaluator to score the matcher. Pure data — no DB access.
  class GoldSet
    Entry = Data.define(:source_object, :targets, :note)
    FieldPair = Data.define(:source_object, :source_field, :targets)

    DEFAULT_PATH = Rails.root.join("config", "mapping_gold_set.yml")

    def initialize(path: DEFAULT_PATH)
      @data = YAML.safe_load_file(path) || {}
    end

    # Source objects with a known correct target (scored for precision/recall).
    def mapped
      @mapped ||= Array(@data["mapped"]).map do |row|
        Entry.new(source_object: row["source_object"], targets: Array(row["targets"]), note: row["note"])
      end
    end

    # Source objects that should have NO confident target yet (gap-discovery).
    def no_target
      @no_target ||= Array(@data["no_target"]).map do |row|
        Entry.new(source_object: row["source_object"], targets: [], note: row["note"])
      end
    end

    def source_objects
      (mapped + no_target).map(&:source_object)
    end

    # Unambiguous source-field -> target-field pairs for field-level scoring.
    def field_pairs
      @field_pairs ||= Array(@data["fields"]).map do |row|
        object, _, field = row["source"].partition(".")
        FieldPair.new(source_object: object, source_field: field, targets: Array(row["targets"]))
      end
    end
  end
end
