class ExtractionRun < ApplicationRecord
  STATUSES = %w[queued extracting profiling complete complete_with_warnings failed].freeze
  SENSITIVE_RETENTION_DAYS = 30

  belongs_to :user, optional: true
  has_many :sobjects, dependent: :destroy
  has_many :srelationships, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :api_version, presence: true
  validates :directory_token, presence: true, uniqueness: true

  before_validation :assign_directory_token, on: :create
  before_validation :assign_default_retained_until, on: :create

  scope :sensitive, -> { where(include_sensitive: true) }
  scope :purgeable, -> { sensitive.where("retained_until IS NOT NULL AND retained_until < ?", Time.current) }

  STATUSES.each do |s|
    define_method("#{s}?") { status == s }
  end

  def mark_started!(limits_snapshot: nil)
    update!(status: "extracting", started_at: Time.current, limits_at_start: limits_snapshot)
  end

  def mark_complete!(limits_snapshot: nil, content_hash: nil)
    final_status = partial_failures.any? ? "complete_with_warnings" : "complete"
    update!(
      status: final_status,
      completed_at: Time.current,
      limits_at_end: limits_snapshot,
      content_hash: content_hash
    )
  end

  def mark_failed!(error)
    update!(status: "failed", completed_at: Time.current, error_message: error.to_s)
  end

  def record_partial_failure!(object_api_name:, reason:)
    self.partial_failures = partial_failures + [{ "object_api_name" => object_api_name, "reason" => reason }]
    save!
  end

  private

  def assign_directory_token
    return if directory_token.present?
    # Format: 2026-05-24T13-38-22Z plus 4 hex chars to break ties when two runs
    # start in the same second (R20 — distinct directories per run).
    stamp = (started_at || Time.current).utc.strftime("%Y-%m-%dT%H-%M-%SZ")
    self.directory_token = "#{stamp}-#{SecureRandom.hex(2)}"
  end

  def assign_default_retained_until
    return unless include_sensitive
    return if retained_until.present?
    self.retained_until = SENSITIVE_RETENTION_DAYS.days.from_now
  end
end
