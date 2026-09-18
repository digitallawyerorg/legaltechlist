class CompanyProposalApprovalService
  # The statuses that put a proposal in front of a reviewer as work still to do.
  OPEN_STATUSES = %w[pending ready_for_review needs_revision].freeze

  def self.call(**kwargs)
    new(**kwargs).call
  end

  # reviewed_description_digest is the fingerprint of the description the reviewer was
  # actually looking at when they approved. Guarding only the post-approval window was
  # the wrong window: every description lost so far was overwritten while the record was
  # still pending, seconds before the approval landed — 31s, 34s and 194s on the three
  # records that prompted this. If the text has moved since it was rendered, the
  # approval is refused rather than applied to something the reviewer never read.
  def initialize(proposal:, admin_user:, duplicate_override: false, publish: false, reviewed_description_digest: nil)
    @proposal = proposal
    @admin_user = admin_user
    @duplicate_override = duplicate_override
    @publish = publish
    @reviewed_description_digest = reviewed_description_digest.to_s.presence
  end

  def self.digest_for(description)
    Digest::SHA256.hexdigest(description.to_s.strip)
  end

  def call
    raise ArgumentError, "Rejected proposals cannot be approved" if proposal.rejected?
    # Idempotent recovery: if this proposal already minted a company, don't try to
    # create a second one. Promote the existing invisible draft to visible when a
    # publish is requested; otherwise return the existing record unchanged.
    return promote_existing_company if proposal.company_id.present?

    ensure_stale_review!
    ensure_description!
    validate_proposal!

    guard_against_existing_company!

    # The company and the link back to it land together or not at all. A company saved
    # without its proposal link is an orphan the next approval cannot see, so a retry
    # would mint a second one — and the proposal would sit in the queue either way.
    company = nil
    ActiveRecord::Base.transaction do
      company = build_company!
      proposal.update!(
        status: publish ? "published" : "approved_to_draft",
        company: company,
        admin_user: admin_user,
        reviewed_at: Time.current,
        approved_at: Time.current
      )
    end

    company
  end

  private

  attr_reader :proposal, :admin_user, :duplicate_override, :publish, :reviewed_description_digest

  def build_company!
    company = Company.new(company_attributes)
    company.visible = publish
    company.quality_status = "needs_review"
    company.verification_verdict = "human_approved_candidate"
    company.human_reviewed_at = Time.current
    company.quality_reviewed_at = Time.current
    company.canonical_domain = company.canonical_main_domain
    company.fingerprint = company.calculated_fingerprint
    company.save!

    revenue_model_ids = Array(proposal.final_changes["business_model_ids"]).map(&:presence).compact
    if revenue_model_ids.empty? && proposal.final_changes["business_model_id"].present?
      revenue_model_ids = [proposal.final_changes["business_model_id"]]
    end
    company.business_model_ids = revenue_model_ids if revenue_model_ids.any?

    target_client_ids = Array(proposal.final_changes["target_client_ids"]).map(&:presence).compact
    company.target_client_ids = target_client_ids if target_client_ids.any?

    if proposal.final_changes["all_tags"].present?
      company.all_tags = proposal.final_changes["all_tags"]
      company.save!
    end

    company
  end

  # Publish an already-created draft (or no-op if already visible). Publishing is
  # still the sensitive action, so it re-checks duplicate and publish blockers.
  def promote_existing_company
    company = proposal.company

    if publish && !company.visible?
      validate_proposal!
      ActiveRecord::Base.transaction do
        company.update!(visible: true)
        proposal.update!(status: "published", admin_user: admin_user, reviewed_at: Time.current, approved_at: Time.current)
      end
    elsif proposal.status.in?(OPEN_STATUSES)
      # A proposal that already minted a company but still reads as open work is the
      # same item sitting in two queues at once. Approving it again is the reviewer
      # saying "this one is done", so record that instead of handing back the company
      # and leaving the proposal queued with no way to clear it.
      proposal.update!(
        status: company.visible? ? "published" : "approved_to_draft",
        admin_user: admin_user,
        reviewed_at: Time.current,
        approved_at: proposal.approved_at || Time.current
      )
    end

    company
  end

  # Duplicate state is resolved against the index and the open queue as they are now,
  # not as they were when the proposal was created. The message names the match so the
  # operator can act on it without going hunting.
  # Refuse an approval whose subject changed underneath it.
  def ensure_stale_review!
    return if reviewed_description_digest.blank?

    current = self.class.digest_for(proposal.final_changes["description"])
    return if current == reviewed_description_digest

    raise ArgumentError,
          "The description changed after you opened this record — most likely an enrichment ran while you were reviewing. " \
          "Reload the proposal and read the current text before approving."
  end

  def validate_proposal!
    # The same gate every other ingestion path goes through. It forces a fresh resolution
    # rather than reusing anything computed earlier in this process — approval is the
    # moment the answer has to be current, and a sibling proposal may have been resolved
    # (or created) since this one was last looked at — and it routes the record to
    # duplicate resolution before refusing, so a blocked approval leaves the proposal
    # somewhere a reviewer will find it.
    DuplicateGate.enforce!(proposal, override: duplicate_override)
    raise ArgumentError, "Resolve publish blockers before publication: #{publish_blockers.to_sentence}" if publish && publish_blockers.any?
  end

  # Last line of defence, immediately before the row is written. The duplicate check
  # above works off names and domains; this works off the identity fingerprint the
  # Company table itself uses, and so also catches a concurrent approval of the same
  # company from another session or a batch running beside this one.
  def guard_against_existing_company!
    return if duplicate_override

    fingerprint = Company.new(company_attributes).calculated_fingerprint
    return if fingerprint.blank?

    existing = Company.where(fingerprint: fingerprint).first
    return if existing.nil?

    raise ArgumentError, "#{existing.name} (##{existing.id}) already holds this name and domain. Keep that entry and reject this proposal, or approve with the duplicate override if they are genuinely different companies."
  end

  def publish_blockers
    @publish_blockers ||= CompanyProposalQualityService.call(proposal)["blockers"]
  end

  def company_attributes
    changes = proposal.final_changes.slice(*CompanyProposal::EDITABLE_COMPANY_FIELDS)
    changes.except("source_description").merge(
      "category_id" => blank_to_nil(changes["category_id"]),
      "secondary_category_id" => blank_to_nil(changes["secondary_category_id"] || legacy_secondary_category_id(changes)),
      "business_model_id" => blank_to_nil(changes["business_model_id"]),
      "target_client_id" => blank_to_nil(changes["target_client_id"])
    ).except("sub_category_id")
  end

  def legacy_secondary_category_id(changes)
    return if changes["sub_category_id"].blank?

    sub = SubCategory.find_by(id: changes["sub_category_id"])
    Category.find_by(name: sub&.name)&.id
  end

  def blank_to_nil(value)
    value.presence
  end

  def ensure_description!
    return if proposal.final_changes["description"].present?

    CompanyProposalEnrichmentService.call(proposal: proposal, admin_user: admin_user, force: true)
    proposal.reload
  end
end
