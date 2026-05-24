# Refuses to boot if `storage/runs/sensitive/` exists with group- or world-
# readable bits set. The sensitive directory must be 0700 so backups and
# aggregation tools cannot inadvertently widen access to redacted-by-policy
# extraction outputs. Skipped in test (suites manage permissions per-test).
unless Rails.env.test?
  Rails.application.config.after_initialize do
    Runs::RunDirectory.boot_check!
  end
end
