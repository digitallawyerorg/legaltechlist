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
  # Judged only when the identity is actually being set or moved. Two proposals created
  # in the same second by one discovery run can already share an identifier, and
  # re-running this on every save froze both rows: rejecting, merging, approving or
  # editing them each failed on a collision that predated the edit. Creating or renaming
  # an identifier is still refused exactly as before.
  validates :source_identifier, uniqueness: { scope: :source, allow_blank: true },
                                if: -> { source_identifier_changed? || source_changed? }

  scope :recent, -> { order(created_at: :desc) }
  scope :pending_review, -> { where(status: %w[pending ready_for_review needs_revision]) }
  scope :approved_to_draft, -> { where(status: "approved_to_draft") }
  scope :published, -> { where(status: "published") }
  scope :rejected, -> { where(status: "rejected") }
  scope :user_submissions, -> { where(proposal_type: USER_SUBMISSION_TYPES) }
  scope :user_contributions, -> { where(proposal_type: "user_contribution") }
  scope :user_suggestions, -> { where(proposal_type: "user_suggestion") }

  # A proposal parked with its contributor: the next action is the submitter's, not a
  # reviewer's. It deliberately stays inside pending_review — the duplicate queue and
  # the approval path both read that scope — and is instead kept off the Review Tab's
  # default view by Admin::CompanyProposalsController, which gives it its own chip.
  scope :awaiting_contributor, -> {
    where("agent_details #>> '{current_contributor_request,state}' = ?", CompanyProposalReturnService::AWAITING_STATE)
  }
  scope :not_awaiting_contributor, -> {
    where("agent_details #>> '{current_contributor_request,state}' IS DISTINCT FROM ?", CompanyProposalReturnService::AWAITING_STATE)
  }

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

  # Duplicate state resolved against the index and the open queue as they are NOW,
  # not as they were at intake. The stored duplicate_signals column is kept in sync
  # as a cache so list/index queries can still filter on it, but no decision is ever
  # taken from it directly: it was a months-stale snapshot that let duplicates through.
  def current_duplicate_signals(refresh: false)
    return @current_duplicate_signals if @current_duplicate_signals && !refresh

    @current_duplicate_signals = ProposalDuplicateDetectorService.call(
      proposal: self,
      extra_domains: site_evidence_domains
    )
  end

  # Recompute and persist, so the review queue's stored counts match what the gate sees.
  def refresh_duplicate_signals!
    current_duplicate_signals(refresh: true)
    persist_duplicate_signals!
  end

  # Write back whatever has already been resolved this request, without recomputing.
  # Used when a list has just asked each row for its duplicate state: the answer is in
  # hand, and persisting it keeps the stored column converging on the live one.
  def persist_duplicate_signals!
    signals = current_duplicate_signals
    record_duplicate_evidence!(signals)
    update_columns(duplicate_signals: signals) if persisted? && duplicate_signals != signals
    signals
  end

  # An append-only record of what the guard saw, kept because the live view forgets.
  #
  # The stored duplicate_signals column is a cache of the current answer, and the current
  # answer changes when a *related* record changes state: resolving one of two twin
  # proposals drops it out of the comparison set, so the survivor goes from a blocking
  # match to empty arrays, and the evidence that anything was ever wrong goes with it. A
  # proposal that was auto-applied over a blocking duplicate now reads as though it ran
  # on an uncontested row.
  #
  # This entry is written the first time a distinct blocking match is seen and is never
  # rewritten or removed, so the disposition can be audited against what was actually
  # known at the time.
  MAX_DUPLICATE_EVIDENCE_ENTRIES = 20

  def record_duplicate_evidence!(signals = current_duplicate_signals)
    return signals unless persisted? && (signals["blocking"] || signals["advisory"])

    entry = duplicate_evidence_entry(signals)
    history = duplicate_evidence
    return signals if history.any? { |seen| seen["matched"] == entry["matched"] }

    update_columns(agent_details: agent_details.merge(
      "duplicate_evidence" => (history + [entry]).last(MAX_DUPLICATE_EVIDENCE_ENTRIES)
    ))
    signals
  end

  def duplicate_evidence
    Array(agent_details["duplicate_evidence"]).select { |entry| entry.is_a?(Hash) }
  end

  def duplicate_evidence_entry(signals)
    matches = Array(signals["name_matches"]) + Array(signals["domain_matches"])
    {
      "first_seen_at" => Time.current.utc.iso8601,
      "status" => status,
      "confidence" => signals["confidence"],
      # How far the gate took it, not merely what it saw. An entry with no surfacing
      # value predates the threshold and was blocking by definition.
      "surfacing" => signals["blocking"] ? CompanyIdentityMatcher::SURFACING_BLOCKING : CompanyIdentityMatcher::SURFACING_ADVISORY,
      "recommended_action" => signals["recommended_action"],
      "matched" => matches.map { |match| match.slice("id", "name", "match_type", "matched_value", "confidence", "visible", "quality_status", "surfacing") } +
                   Array(signals["proposal_matches"]).map { |match| match.slice("proposal_id", "name", "match_type", "status", "is_older", "surfacing") }
    }
  end

  def duplicate_blocking?
    current_duplicate_signals["blocking"] == true
  end

  # Something matched, but only on a single loose key. Reported to the reviewer and
  # recorded; it does not stop a human's write, and it does stop an unattended one.
  def duplicate_advisory?
    current_duplicate_signals["advisory"] == true
  end

  def duplicate_matches
    signals = current_duplicate_signals
    Array(signals["name_matches"]) + Array(signals["domain_matches"])
  end

  def duplicate_proposal_matches
    Array(current_duplicate_signals["proposal_matches"])
  end

  # Domains discovered by actually fetching the candidate's site, which is what lets
  # the detector spot a rebrand whose declared URL differs from the stored entry's.
  def site_evidence_domains
    pages = Array(agent_details.dig("site_evidence", "pages"))
    pages.filter_map { |page| Company.canonical_domain_for(page["final_url"].presence || page["url"]) }.uniq
  end

  def quality_report
    CompanyProposalQualityService.call(self)
  end

  # The stored report from the last enrichment, used by list views to avoid recomputing
  # for every row. Reports written before the verification gate existed are treated as
  # absent rather than trusted: they would tell a reviewer a record is ready while the
  # detail view blocks it. Ignoring them makes the lists self-heal as records are
  # re-enriched, with no backfill needed.
  QUALITY_REPORT_REQUIRED_KEY = "verification_state".freeze

  def cached_quality_report
    return nil unless agent_details.is_a?(Hash)

    report = agent_details["quality"]
    return nil unless report.is_a?(Hash) && report[QUALITY_REPORT_REQUIRED_KEY].present?

    report
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

  # True when this proposal originated from an external human submitter (public
  # contribution/suggestion form) rather than from discovery or the curator.
  # Such proposals are lower-trust and must never be published/applied autonomously.
  def externally_submitted?
    submitter_email.present?
  end

  def user_contribution?
    proposal_type == "user_contribution"
  end

  def user_suggestion?
    proposal_type == "user_suggestion"
  end
end
