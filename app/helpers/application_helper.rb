module ApplicationHelper
  STATUS_BADGE_CLASSES = {
    "queued" => "bg-slate-100 text-slate-700",
    "extracting" => "bg-blue-100 text-blue-800",
    "profiling" => "bg-indigo-100 text-indigo-800",
    "complete" => "bg-emerald-100 text-emerald-800",
    "complete_with_warnings" => "bg-amber-100 text-amber-900",
    "failed" => "bg-rose-100 text-rose-800"
  }.freeze

  SENSITIVITY_LABELS = {
    "safe" => "Safe",
    "pii" => "PII",
    "financial" => "Financial",
    "pii_and_financial" => "PII + Financial",
    "unknown_sensitivity" => "Unknown — pending classification"
  }.freeze

  def status_badge(status)
    classes = STATUS_BADGE_CLASSES.fetch(status, "bg-slate-100 text-slate-700")
    content_tag(:span, status.tr("_", " "), class: "inline-block rounded px-2 py-0.5 text-xs font-medium #{classes}")
  end

  def sensitivity_label(sensitivity)
    SENSITIVITY_LABELS.fetch(sensitivity.to_s, sensitivity.to_s)
  end

  def sensitive_field?(sfield)
    sfield.sensitivity.to_s != "safe"
  end

  def can_view_sensitive_values?(run, user)
    return false if user.nil?
    return true unless run
    run.include_sensitive && user.sensitive_data_access?
  end

  def redacted_cell(sfield)
    content_tag(:span,
                class: "inline-flex items-center gap-1 text-slate-500",
                title: "Redacted for #{sensitivity_label(sfield.sensitivity)}. Requires sensitive_data_access role and a sensitive run.") do
      concat content_tag(:span, "lock", class: "text-xs")
      concat content_tag(:span, sensitivity_label(sfield.sensitivity), class: "text-xs italic")
    end
  end

  def time_ago_or_dash(time)
    return "—" if time.nil?
    "#{time_ago_in_words(time)} ago"
  end
end
