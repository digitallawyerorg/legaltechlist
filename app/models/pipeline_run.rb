class PipelineRun < ActiveRecord::Base
  STATUSES = %w[pending running succeeded failed].freeze

  validates :name, presence: true
  validates :run_type, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :records_processed, numericality: { greater_than_or_equal_to: 0 }

  scope :recent, -> { order(created_at: :desc) }
  scope :running, -> { where(status: "running") }
  scope :failed, -> { where(status: "failed") }

  def mark_running!
    update!(status: "running", started_at: Time.current)
  end

  def mark_succeeded!(records_processed: self.records_processed, details: self.details)
    update!(
      status: "succeeded",
      records_processed: records_processed,
      details: details,
      finished_at: Time.current
    )
  end

  def mark_failed!(message, details: self.details)
    update!(
      status: "failed",
      error_message: message,
      details: details,
      finished_at: Time.current
    )
  end
end
