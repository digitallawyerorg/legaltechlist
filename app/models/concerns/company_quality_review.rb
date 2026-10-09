module CompanyQualityReview
  extend ActiveSupport::Concern

  REVIEW_STATE_LABELS = {
    "not_reviewed" => "Not reviewed",
    "in_review" => "In review",
    "awaiting_contributor" => "Awaiting contributor",
    "verified" => "Verified",
    "rejected" => "Rejected"
  }.freeze

  REVIEW_STATE_FILTER_OPTIONS = REVIEW_STATE_LABELS.freeze

  QUALITY_STATUS_OPTIONS = {
    "" => "Unspecified",
    "needs_review" => "Needs review",
    "awaiting_contributor" => "Awaiting contributor",
    "verified" => "Verified",
    "source_verified" => "Source verified",
    "rejected" => "Rejected"
  }.freeze

  VERIFICATION_VERDICT_OPTIONS = {
    "" => "Unspecified",
    "human_confirmed" => "Human confirmed",
    "human_rejected" => "Human rejected",
    "human_approved_candidate" => "Human approved (candidate)",
    "needs_human_review" => "Needs human review",
    "awaiting_contributor_update" => "Awaiting contributor update",
    "likely_valid_needs_human_confirmation" => "Likely valid",
    "manual_review_required" => "Manual review required",
    "automated_import_draft" => "Automated import draft",
    "agent_published_source_verified" => "Agent published",
    "reject_or_hide_pending_review" => "Reject or hide",
    "duplicate_consolidation_keeper" => "Duplicate consolidation keeper",
    "out_of_scope_review" => "Out of scope review",
    "hidden_pending_review" => "Hidden pending review"
  }.freeze

  # Verdicts recording that a person, or the scope pass, took a record off the public
  # site on purpose. No automated publish may undo one: the import worker used to
  # re-publish "already drafted" rows over them, which is how ~70 law firms hidden as
  # out of scope (Greenberg Traurig among them) came back as live "inactive" entries.
  DELIBERATELY_HIDDEN_VERDICTS = %w[human_rejected out_of_scope_review awaiting_contributor_update hidden_pending_review].freeze

  included do
    scope :review_state_not_reviewed, -> { where(quality_status: [nil, ""]).where(human_reviewed_at: nil) }
    scope :review_state_in_review, -> { where(quality_status: "needs_review") }
    scope :review_state_verified, -> { where(quality_status: %w[verified source_verified]) }
    scope :review_state_rejected, -> { where(quality_status: "rejected") }
    # Parked with the contributor. Deliberately its own state so it leaves the active
    # reviewer queues instead of falling back into "not reviewed".
    scope :review_state_awaiting_contributor, -> { where(quality_status: CompanyReviewMarkService::RETURNED_STATUS) }

    # The publishing workload: everything except records already decided (verified or
    # rejected) and records parked with their contributor.
    scope :needs_publishing_review, -> { where(quality_status: [nil, "", "needs_review"]) }

    scope :with_review_state, ->(state) {
      case state.to_s
      when "not_reviewed" then review_state_not_reviewed
      when "in_review" then review_state_in_review
      when "verified" then review_state_verified
      when "rejected" then review_state_rejected
      when "awaiting_contributor" then review_state_awaiting_contributor
      else all
      end
    }
  end

  def deliberately_hidden?
    quality_status.in?(["rejected", CompanyReviewMarkService::RETURNED_STATUS]) ||
      verification_verdict.in?(DELIBERATELY_HIDDEN_VERDICTS)
  end

  # Out of scope is a verdict about the index, not about the business, so lifecycle
  # status is left alone. Setting it to "inactive" here told readers live law firms
  # had shut down, and inflated the public inactive count.
  def hide_as_out_of_scope!
    update!(visible: false, quality_status: "rejected", verification_verdict: "out_of_scope_review")
  end

  def review_state
    return "rejected" if quality_status == "rejected"
    return "awaiting_contributor" if quality_status == CompanyReviewMarkService::RETURNED_STATUS
    return "verified" if quality_status.in?(%w[verified source_verified])
    return "in_review" if quality_status == "needs_review"

    "not_reviewed"
  end

  def review_state_label
    REVIEW_STATE_LABELS.fetch(review_state)
  end

  def review_state_badge_class
    case review_state
    when "verified" then "text-bg-success"
    when "in_review" then "text-bg-warning text-dark"
    when "rejected" then "text-bg-danger"
    else "text-bg-secondary"
    end
  end

  def review_verdict_tooltip
    return if verification_verdict.blank?

    "Verdict: #{verification_verdict.humanize}"
  end

  def last_reviewed_at
    [human_reviewed_at, quality_reviewed_at].compact.max
  end

  def last_reviewed_label
    return "Never reviewed" if last_reviewed_at.blank?

    last_reviewed_at.to_date.to_fs(:long)
  end

  class_methods do
    def quality_status_options_for(company)
      options = QUALITY_STATUS_OPTIONS.dup
      status = company&.quality_status.to_s
      options[status] = status.humanize if status.present? && !options.key?(status)
      options
    end

    def verification_verdict_options_for(company)
      options = VERIFICATION_VERDICT_OPTIONS.dup
      verdict = company&.verification_verdict.to_s
      options[verdict] = verdict.humanize if verdict.present? && !options.key?(verdict)
      options
    end
  end
end
