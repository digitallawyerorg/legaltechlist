class CompanyProposal < ActiveRecord::Base
  include TaxonomyCompleteness

  STATUSES = %w[pending ready_for_review needs_revision approved_to_draft published rejected].freeze
  PROPOSAL_TYPES = %w[atlas_candidate discovery_candidate user_contribution user_suggestion].freeze
  USER_SUBMISSION_TYPES = %w[user_contribution user_suggestion].freeze

  belongs_to :admin_user, optional: true
  belongs_to :company, optional: true

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :proposal_type, presence: true, inclusion: { in: PROPOSAL_TYPES }
  validates :source, presence: true
  validates :source_identifier, uniqueness: { scope: :source, allow_blank: true }

  scope :recent, -> { order(created_at: :desc) }
  scope :pending_review, -> { where(status: %w[pending ready_for_review needs_revision]) }
  scope :approved_to_draft, -> { where(status: "approved_to_draft") }
  scope :published, -> { where(status: "published") }
  scope :rejected, -> { where(status: "rejected") }
  scope :user_submissions, -> { where(proposal_type: USER_SUBMISSION_TYPES) }
  scope :user_contributions, -> { where(proposal_type: "user_contribution") }
  scope :user_suggestions, -> { where(proposal_type: "user_suggestion") }

  EDITABLE_COMPANY_FIELDS = %w[
    name
    main_url
    location
    founded_date
    status
    description
    category_id
    secondary_category_id
    business_model_id
    business_model_ids
    target_client_id
    target_client_ids
    all_tags
    crunchbase_url
    linkedin_url
    total_funding_amount_usd
    funding_status
    number_of_funding_rounds
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

  def quality_report
    CompanyProposalQualityService.call(self)
  end

  def cached_quality_report
    agent_details.is_a?(Hash) ? agent_details["quality"] : nil
  end

  def publish_ready?
    quality_report["publish_ready"]
  end

  def approved_to_draft?
    status == "approved_to_draft"
  end

  def rejected?
    status == "rejected"
  end

  def user_submission?
    proposal_type.in?(USER_SUBMISSION_TYPES)
  end

  def user_contribution?
    proposal_type == "user_contribution"
  end

  def user_suggestion?
    proposal_type == "user_suggestion"
  end
end
