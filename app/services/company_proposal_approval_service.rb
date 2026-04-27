class CompanyProposalApprovalService
  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(proposal:, admin_user:, duplicate_override: false)
    @proposal = proposal
    @admin_user = admin_user
    @duplicate_override = duplicate_override
  end

  def call
    validate_proposal!

    company = Company.new(company_attributes)
    company.visible = false
    company.quality_status = "needs_review"
    company.verification_verdict = "human_approved_candidate"
    company.human_reviewed_at = Time.current
    company.quality_reviewed_at = Time.current
    company.canonical_domain = company.canonical_main_domain
    company.fingerprint = company.calculated_fingerprint
    company.save!

    proposal.update!(
      status: "approved_to_draft",
      company: company,
      admin_user: admin_user,
      reviewed_at: Time.current,
      approved_at: Time.current
    )

    company
  end

  private

  attr_reader :proposal, :admin_user, :duplicate_override

  def validate_proposal!
    raise ArgumentError, "Rejected proposals cannot be approved" if proposal.rejected?
    raise ArgumentError, "Proposal has already created a company draft" if proposal.company_id.present?
    raise ArgumentError, "Resolve duplicate signals or confirm override before approval" if proposal.duplicate_blocking? && !duplicate_override
  end

  def company_attributes
    changes = proposal.final_changes.slice(*CompanyProposal::EDITABLE_COMPANY_FIELDS)
    changes.except("source_description").merge(
      "category_id" => blank_to_nil(changes["category_id"]),
      "sub_category_id" => blank_to_nil(changes["sub_category_id"]),
      "business_model_id" => blank_to_nil(changes["business_model_id"]),
      "target_client_id" => blank_to_nil(changes["target_client_id"])
    )
  end

  def blank_to_nil(value)
    value.presence
  end
end
