class CompanyImportRun < ActiveRecord::Base
  STATUSES = %w[pending running paused succeeded failed].freeze

  has_many :company_import_rows, dependent: :destroy

  validates :source, presence: true
  validates :filename, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :total_rows, numericality: { greater_than_or_equal_to: 0 }
  validates :processed_rows, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(status: %w[pending running]) }
  scope :recent, -> { order(created_at: :desc) }

  def mark_running!
    update!(status: "running", started_at: started_at || Time.current)
  end

  def mark_paused!
    update!(status: "paused")
  end

  def mark_succeeded!
    refresh_summary!
    update!(status: "succeeded", finished_at: Time.current)
  end

  def mark_failed!(message)
    refresh_summary!
    update!(status: "failed", error_message: message, finished_at: Time.current)
  end

  def refresh_summary!
    counts = company_import_rows.group(:status).count
    actions = company_import_rows.where.not(action: nil).group(:action).count
    update!(
      processed_rows: company_import_rows.where(status: CompanyImportRow::TERMINAL_STATUSES).count,
      summary: {
        "statuses" => counts,
        "actions" => actions,
        "pending" => company_import_rows.pending.count,
        "updated_at" => Time.current.utc.iso8601
      }
    )
  end
end
