class CompanyProposal < ActiveRecord::Base
  STATUSES = %w[pending ready_for_review needs_revision approved_to_draft rejected].freeze
  PROPOSAL_TYPES = %w[atlas_candidate].freeze

  belongs_to :admin_user, optional: true
  belongs_to :company, optional: true

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :proposal_type, presence: true, inclusion: { in: PROPOSAL_TYPES }
  validates :source, presence: true
  validates :source_identifier, uniqueness: { scope: :source, allow_blank: true }

  scope :recent, -> { order(created_at: :desc) }
  scope :pending_review, -> { where(status: %w[pending ready_for_review needs_revision]) }
  scope :approved_to_draft, -> { where(status: "approved_to_draft") }
  scope :rejected, -> { where(status: "rejected") }

  EDITABLE_COMPANY_FIELDS = %w[
    name
    main_url
    location
    founded_date
    status
    description
    category_id
    sub_category_id
    business_model_id
    target_client_id
    crunchbase_url
    linkedin_url
    total_funding_amount_usd
    funding_status
    number_of_funding_rounds
    employee_count
    founders
    source
    source_url
  ].freeze

  def display_name
    final_changes["name"].presence || proposed_changes["name"].presence || source_payload["name"].presence || "Untitled proposal"
  end

  def editable_changes
    proposed_changes.slice(*EDITABLE_COMPANY_FIELDS).merge(final_changes.slice(*EDITABLE_COMPANY_FIELDS))
  end

  def duplicate_blocking?
    Array(duplicate_signals["name_matches"]).any? || Array(duplicate_signals["domain_matches"]).any?
  end

  def approved_to_draft?
    status == "approved_to_draft"
  end

  def rejected?
    status == "rejected"
  end
end
