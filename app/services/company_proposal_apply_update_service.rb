class CompanyProposalApplyUpdateService
  def self.call(proposal:, admin_user:, publish: false, duplicate_override: false)
    new(proposal: proposal, admin_user: admin_user, publish: publish, duplicate_override: duplicate_override).call
  end

  def initialize(proposal:, admin_user:, publish: false, duplicate_override: false)
    @proposal = proposal
    @admin_user = admin_user
    @publish = publish
    @duplicate_override = ActiveModel::Type::Boolean.new.cast(duplicate_override)
  end

  def call
    raise ArgumentError, "Only user suggestions can be applied to existing companies" unless proposal.user_suggestion?
    raise ArgumentError, "Proposal is not linked to a company" if proposal.company_id.blank?

    # Duplicate detection is a mandatory validation, not a step one ingestion path gets to
    # skip. This was the write with no gate in front of it: it edits a live, published
    # company, it runs autonomously under MCP_CURATOR_AUTOAPPLY_UPDATES, and the approval
    # tool routed every suggestion straight here past the quality gate and the duplicate
    # check both. So a suggestion whose real subject is a different entry — or whose twin
    # was still open in the queue — overwrote a published record instead of being compared
    # against it.
    #
    # A suggestion matching the company it is already attached to is the record commenting
    # on itself, and the matcher excludes that. Any other blocking match stops the write
    # here and the record goes to duplicate resolution, where the comparison it needs can
    # actually be made.
    DuplicateGate.enforce!(proposal, override: duplicate_override)

    company = proposal.company
    changes = proposal.final_changes.slice(*CompanyProposal::EDITABLE_COMPANY_FIELDS)
    scalar_changes = changes.except("business_model_ids", "target_client_ids", "all_tags")

    # This path writes straight onto a live company, and it runs autonomously when
    # MCP_CURATOR_AUTOAPPLY_UPDATES is on. It was the remaining way a description could
    # be replaced on a public record with no lock respected, no reason recorded and no
    # history — so the same rules that govern a direct edit apply here.
    scalar_changes = guard_description!(company, scalar_changes)
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

  attr_reader :proposal, :admin_user, :publish, :duplicate_override

  # A locked description is not overwritten by an automated apply. A permitted change
  # records what it replaced and why, the same as update_company_field.
  def guard_description!(company, scalar_changes)
    incoming = scalar_changes["description"].to_s.strip
    return scalar_changes if incoming.blank? || incoming == company.description.to_s.strip

    if description_locked?(company)
      raise ArgumentError, "#{company.name}'s description is locked against automated changes. Unlock it, or edit it directly with a reason."
    end

    review = company.quality_review.is_a?(Hash) ? company.quality_review.deep_dup : {}
    review["field_edits"] = Array(review["field_edits"]) + [{
      "at" => Time.current.utc.iso8601,
      "via" => "apply_user_suggestion",
      "reason" => "Applied user suggestion #{proposal.id}#{" by #{admin_user.email}" if admin_user.respond_to?(:email)}",
      "changes" => { "description" => { "from" => company.description, "to" => incoming } }
    }]
    company.quality_review = review
    scalar_changes
  end

  def description_locked?(company)
    company.quality_review.is_a?(Hash) && company.quality_review["description_locked"] == true
  end

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
