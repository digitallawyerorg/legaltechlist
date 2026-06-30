module CompanyQualityReview
  extend ActiveSupport::Concern

  REVIEW_STATE_LABELS = {
    "not_reviewed" => "Not reviewed",
    "in_review" => "In review",
    "verified" => "Verified",
    "rejected" => "Rejected"
  }.freeze

  REVIEW_STATE_FILTER_OPTIONS = REVIEW_STATE_LABELS.freeze

  QUALITY_STATUS_OPTIONS = {
    "" => "Unspecified",
    "needs_review" => "Needs review",
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
    "likely_valid_needs_human_confirmation" => "Likely valid",
    "manual_review_required" => "Manual review required",
    "automated_import_draft" => "Automated import draft",
    "agent_published_source_verified" => "Agent published",
    "reject_or_hide_pending_review" => "Reject or hide",
    "duplicate_consolidation_keeper" => "Duplicate consolidation keeper",
    "out_of_scope_review" => "Out of scope review"
  }.freeze

  included do
    scope :review_state_not_reviewed, -> { where(quality_status: [nil, ""]).where(human_reviewed_at: nil) }
    scope :review_state_in_review, -> { where(quality_status: "needs_review") }
    scope :review_state_verified, -> { where(quality_status: %w[verified source_verified]) }
    scope :review_state_rejected, -> { where(quality_status: "rejected") }

    scope :with_review_state, ->(state) {
      case state.to_s
      when "not_reviewed" then review_state_not_reviewed
      when "in_review" then review_state_in_review
      when "verified" then review_state_verified
      when "rejected" then review_state_rejected
      else all
      end
    }
  end

  def review_state
    return "rejected" if quality_status == "rejected"
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
