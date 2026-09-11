class PipelineRun < ActiveRecord::Base
  # "partial" is a real outcome, not a tidied-up failure: a reviewer action that saved
  # some of what it was asked to save is neither a success nor a clean failure, and
  # flattening it into either loses the only detail worth looking up afterwards.
  STATUSES = %w[pending running succeeded failed partial].freeze

  validates :name, presence: true
  validates :run_type, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :records_processed, numericality: { greater_than_or_equal_to: 0 }

  scope :recent, -> { order(created_at: :desc) }
  scope :running, -> { where(status: "running") }
  scope :failed, -> { where(status: "failed") }
  scope :for_company, ->(company) { where("(details ->> 'company_id')::bigint = ?", company.id) }

  # Reviewer actions and agent runs share this table; only the agent runs carry a
  # findings packet, so only they have a review page to link to.
  def reviewer_action?
    run_type == ReviewerActionAudit::RUN_TYPE
  end

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
