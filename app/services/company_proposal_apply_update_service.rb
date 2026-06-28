class CompanyProposalApplyUpdateService
  def self.call(proposal:, admin_user:, publish: false)
    new(proposal: proposal, admin_user: admin_user, publish: publish).call
  end

  def initialize(proposal:, admin_user:, publish: false)
    @proposal = proposal
    @admin_user = admin_user
    @publish = publish
  end

  def call
    raise ArgumentError, "Only user suggestions can be applied to existing companies" unless proposal.user_suggestion?
    raise ArgumentError, "Proposal is not linked to a company" if proposal.company_id.blank?

    company = proposal.company
    changes = proposal.final_changes.slice(*CompanyProposal::EDITABLE_COMPANY_FIELDS)
    scalar_changes = changes.except("business_model_ids", "target_client_ids", "all_tags")
    company.assign_attributes(scalar_changes)
    company.visible = true if publish
    company.human_reviewed_at = Time.current
    company.quality_reviewed_at = Time.current
    company.save!

    apply_associations!(company, changes)
    apply_tags!(company, changes["all_tags"]) if changes.key?("all_tags")

    proposal.update!(
      status: "published",
      admin_user: admin_user,
      reviewed_at: Time.current,
      approved_at: Time.current
    )

    company
  end

  private

  attr_reader :proposal, :admin_user, :publish

  def apply_associations!(company, changes)
    revenue_model_ids = Array(changes["business_model_ids"]).map(&:presence).compact
    revenue_model_ids = [changes["business_model_id"]] if revenue_model_ids.empty? && changes["business_model_id"].present?
    company.business_model_ids = revenue_model_ids if revenue_model_ids.any?

    target_client_ids = Array(changes["target_client_ids"]).map(&:presence).compact
    target_client_ids = [changes["target_client_id"]] if target_client_ids.empty? && changes["target_client_id"].present?
    company.target_client_ids = target_client_ids if target_client_ids.any?
  end

  def apply_tags!(company, tags_value)
    return if tags_value.blank?

    company.all_tags = tags_value
    company.save!
  end
end
