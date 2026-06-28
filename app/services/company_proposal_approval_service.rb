class CompanyProposalApprovalService
  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(proposal:, admin_user:, duplicate_override: false, publish: false)
    @proposal = proposal
    @admin_user = admin_user
    @duplicate_override = duplicate_override
    @publish = publish
  end

  def call
    validate_base_proposal!
    ensure_description!
    validate_proposal!

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

    proposal.update!(
      status: publish ? "published" : "approved_to_draft",
      company: company,
      admin_user: admin_user,
      reviewed_at: Time.current,
      approved_at: Time.current
    )

    company
  end

  private

  attr_reader :proposal, :admin_user, :duplicate_override, :publish

  def validate_base_proposal!
    raise ArgumentError, "Rejected proposals cannot be approved" if proposal.rejected?
    raise ArgumentError, "Proposal has already created a company draft" if proposal.company_id.present?
  end

  def validate_proposal!
    raise ArgumentError, "Resolve duplicate signals or confirm override before approval" if proposal.duplicate_blocking? && !duplicate_override
    raise ArgumentError, "Resolve publish blockers before publication: #{publish_blockers.to_sentence}" if publish && publish_blockers.any?
  end

  def publish_blockers
    @publish_blockers ||= CompanyProposalQualityService.call(proposal)["blockers"]
  end

  def company_attributes
    changes = proposal.final_changes.slice(*CompanyProposal::EDITABLE_COMPANY_FIELDS)
    changes.except("source_description").merge(
      "category_id" => blank_to_nil(changes["category_id"]),
      "secondary_category_id" => blank_to_nil(changes["secondary_category_id"]),
      "sub_category_id" => blank_to_nil(changes["sub_category_id"]),
      "business_model_id" => blank_to_nil(changes["business_model_id"]),
      "target_client_id" => blank_to_nil(changes["target_client_id"])
    )
  end

  def blank_to_nil(value)
    value.presence
  end

  def ensure_description!
    return if proposal.final_changes["description"].present?

    CompanyProposalEnrichmentService.call(proposal: proposal, admin_user: admin_user)
    proposal.reload
  end
end
