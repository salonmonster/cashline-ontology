module Mapping
  # Assembles a compact, role-focused "dossier" for a field on either side of the
  # mapping. The matcher's weakness is that it sees only names; a dossier adds the
  # signals that actually encode a field's *functional role* — relationships,
  # data distribution, formula, picklist vocabulary, parent-object role — which
  # both the embedding retrieval and the LLM adjudicator (later units) consume.
  #
  # Two design constraints from the research:
  #   1. Context sweet spot — too little OR too much hurts (VLDB'24). Everything
  #      here is capped/summarized, not dumped.
  #   2. Sensitivity gate — value-derived stats (top_values, samples, numeric/date
  #      ranges) are emitted ONLY for `safe` fields. Structural stats (null_rate,
  #      distinct_count) are always safe. Mirrors the PII gate in EmbeddingMatcher.
  class Dossier
    PICKLIST_CAP = 15
    TOP_VALUES_CAP = 6
    ENUM_CAP = 20

    def initialize(snapshot: nil)
      @snapshot = snapshot
    end

    # Structured dossier for a Sailfin source field. For non-`safe` fields the
    # dossier is structural-metadata-only (api_name, type, references, structural
    # counts) — field *content* (label, help, formula, picklist vocabulary) and
    # value-derived stats are withheld, so the dossier is safe to transmit to any
    # external model. Mirrors the strict embedding transmission gate.
    def source(sfield)
      rd = sfield.raw_describe || {}
      sobject = sfield.sobject
      safe = sfield.sensitivity.to_s == "safe"

      field = { api_name: sfield.api_name, type: sfield.data_type, required: sfield.nillable == false }
      if safe
        field[:label] = sfield.label.presence
        field[:help] = rd["inlineHelpText"].presence
        field[:formula] = sfield.calculated_formula.presence
      end

      {
        side: "sailfin",
        object: {
          api_name: sobject.api_name,
          label: sobject.label.presence,
          cluster: cluster_name(sobject),
          record_count: record_count(sobject)
        }.compact,
        field: field.compact,
        references: Array(rd["referenceTo"]).compact_blank.presence,
        picklist: (safe ? picklist_sample(sfield).presence : nil),
        profile: source_profile(sfield),
        sensitivity: sfield.sensitivity
      }.compact
    end

    # Structured dossier for a cashline target field (requires a snapshot).
    def target(class_name, field_name)
      raise ArgumentError, "snapshot required for target dossiers" unless @snapshot
      col = @snapshot.field(class_name, field_name)
      return nil unless col

      cd = class_descriptor(class_name)
      {
        side: "cashline",
        class_name: class_name,
        namespace: cd&.dig("namespace"),
        field: {
          name: col["name"],
          type: col["type"],
          null: col["null"],
          default: col["default"],
          comment: col["comment"].presence
        }.compact,
        enum_values: enum_sample(col),
        belongs_to: belongs_to_for(cd, field_name),
        relations: relations_summary(cd).presence
      }.compact
    end

    # Compact text rendering for embedding / LLM input.
    def render(dossier)
      dossier[:side] == "sailfin" ? render_source(dossier) : render_target(dossier)
    end

    private

    # ---- source helpers ----

    def source_profile(sfield)
      fp = sfield.field_profiles.first
      return nil unless fp

      profile = { null_rate: fp.null_rate, distinct: fp.distinct_count }.compact
      if sfield.sensitivity.to_s == "safe"
        top = Array(fp.top_values).first(TOP_VALUES_CAP).filter_map do |h|
          v = h["value"] || h["v"]
          v.nil? ? nil : { value: v, count: h["count"] || h["c"] }
        end
        profile[:top_values] = top if top.any?
        profile[:numeric_range] = [ fp.min_value, fp.max_value ] if fp.min_value || fp.max_value
        profile[:date_range] = [ fp.min_date, fp.max_date ] if fp.min_date || fp.max_date
      end
      profile.presence
    end

    def picklist_sample(sfield)
      values = sfield.spicklist_values.select(&:active).map(&:value)
      values = sfield.spicklist_values.map(&:value) if values.empty?
      values.compact.first(PICKLIST_CAP)
    end

    def cluster_name(sobject)
      Cluster.where(id: ClusterAssignment.where(sobject_id: sobject.id).select(:cluster_id)).pluck(:name).first
    end

    def record_count(sobject)
      ObjectProfile.where(sobject_id: sobject.id).order(profiled_at: :desc).limit(1).pick(:record_count)
    end

    # ---- target helpers ----

    def class_descriptor(class_name)
      @snapshot.class_descriptors.find { |c| c["class_name"] == class_name }
    end

    def enum_sample(col)
      vals = col["enum_values"]
      return nil if vals.blank?
      vals.keys.first(ENUM_CAP)
    end

    # If this field is a foreign key, the belongs_to target it implements.
    def belongs_to_for(cd, field_name)
      return nil unless cd
      assoc = Array(cd["associations"]).find { |a| a["macro"] == "belongs_to" && a["foreign_key"] == field_name }
      assoc && { name: assoc["name"], class_name: assoc["class_name"] }
    end

    # The entity's belongs_to targets — cheap role context for the parent class.
    def relations_summary(cd)
      return [] unless cd
      Array(cd["associations"]).select { |a| a["macro"] == "belongs_to" }.map { |a| a["class_name"] }.uniq
    end

    # ---- rendering ----

    def render_source(d)
      obj = d[:object]
      lines = []
      lines << "[sailfin] #{obj[:api_name]}.#{d[:field][:api_name]}"
      meta = [ obj[:label] && %("#{obj[:label]}"), obj[:cluster] && "cluster=#{obj[:cluster]}", obj[:record_count] && "~#{obj[:record_count]} rows" ].compact.join(" · ")
      lines << "object: #{meta}" if meta.present?
      f = d[:field]
      ftype = [ f[:type], f[:required] ? "required" : nil ].compact.join(" · ")
      lines << "field: #{f[:label] || f[:api_name]} (#{ftype})"
      lines << "help: #{f[:help]}" if f[:help]
      lines << "formula: #{f[:formula]}" if f[:formula]
      lines << "references: #{d[:references].join(', ')}" if d[:references]
      lines << "picklist: #{d[:picklist].join(', ')}" if d[:picklist]
      lines << "data: #{render_profile(d[:profile])}" if d[:profile]
      lines << "sensitivity: #{d[:sensitivity]}" if d[:sensitivity] && d[:sensitivity] != "safe"
      lines.join("\n")
    end

    def render_target(d)
      f = d[:field]
      lines = []
      lines << "[cashline] #{d[:class_name]}.#{f[:name]} (#{f[:type]})"
      lines << "comment: #{f[:comment]}" if f[:comment]
      lines << "enum: #{d[:enum_values].join(', ')}" if d[:enum_values]
      lines << "fk -> #{d[:belongs_to][:class_name]}" if d[:belongs_to]
      lines << "#{d[:class_name]} relates to: #{d[:relations].join(', ')}" if d[:relations]
      lines.join("\n")
    end

    def render_profile(p)
      parts = []
      parts << "null=#{(p[:null_rate].to_f * 100).round}%" if p[:null_rate]
      parts << "distinct=#{p[:distinct]}" if p[:distinct]
      if p[:top_values]
        parts << "top=[#{p[:top_values].map { |t| "#{t[:value]}(#{t[:count]})" }.join(', ')}]"
      end
      parts << "range=#{p[:numeric_range].join('..')}" if p[:numeric_range]
      parts << "dates=#{p[:date_range].join('..')}" if p[:date_range]
      parts.join(" ")
    end
  end
end
