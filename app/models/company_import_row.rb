class CompanyImportRow < ActiveRecord::Base
  STATUSES = %w[pending processing completed held failed skipped].freeze
  TERMINAL_STATUSES = %w[completed held failed skipped].freeze

  belongs_to :company_import_run
  belongs_to :company_proposal, optional: true
  belongs_to :company, optional: true

  validates :row_number, presence: true, numericality: { greater_than: 0 }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :row_number, uniqueness: { scope: :company_import_run_id }

  scope :pending, -> { where(status: "pending").order(:row_number) }
  scope :failed, -> { where(status: "failed") }
  scope :terminal, -> { where(status: TERMINAL_STATUSES) }

  def mark_processing!
    update!(
      status: "processing",
      attempts: attempts + 1,
      locked_at: Time.current,
      started_at: Time.current,
      error_message: nil,
      error_class: nil
    )
  end

  def mark_completed!(result:, quality: {})
    update_from_result!("completed", result, quality)
  end

  def mark_held!(result:, quality: {})
    update_from_result!("held", result, quality)
  end

  def mark_skipped!(result:)
    update_from_result!("skipped", result, {})
  end

  def mark_failed!(error)
    update!(
      status: "failed",
      error_message: error.message,
      error_class: error.class.name,
      finished_at: Time.current,
      locked_at: nil
    )
  end

  private

  def update_from_result!(new_status, result, quality)
    update!(
      status: new_status,
      action: result["action"],
      company_proposal_id: result["proposal_id"],
      company_id: result["company_id"],
      result_payload: result,
      quality_report: quality,
      finished_at: Time.current,
      locked_at: nil
    )
  end
end
