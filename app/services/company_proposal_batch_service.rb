class CompanyProposalBatchService
  BATCH_ACTIONS = %w[reenrich mark_needs_revision publish].freeze

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(proposals:, admin_user:, action:, duplicate_override: false)
    @proposals = proposals
    @admin_user = admin_user
    @action = action.to_s
    @duplicate_override = duplicate_override
  end

  def call
    validate_action!
    proposals.map { |proposal| perform(proposal) }
  end

  private

  attr_reader :proposals, :admin_user, :action, :duplicate_override

  def validate_action!
    raise ArgumentError, "Unknown batch action" unless BATCH_ACTIONS.include?(action)
    raise ArgumentError, "Select at least one proposal" if proposals.empty?
  end

  def perform(proposal)
    case action
    when "reenrich"
      CompanyProposalEnrichmentService.call(proposal: proposal, admin_user: admin_user)
      { "proposal_id" => proposal.id, "status" => "reenriched" }
    when "mark_needs_revision"
      proposal.update!(status: "needs_revision", admin_user: admin_user, reviewed_at: Time.current)
      { "proposal_id" => proposal.id, "status" => "needs_revision" }
    when "publish"
      quality = CompanyProposalQualityService.call(proposal)
      raise ArgumentError, "#{proposal.display_name} is not publish-ready: #{Array(quality['blockers']).to_sentence}" unless quality["publish_ready"]

      company = CompanyProposalApprovalService.call(proposal: proposal, admin_user: admin_user, duplicate_override: duplicate_override, publish: true)
      { "proposal_id" => proposal.id, "status" => "published", "company_id" => company.id }
    end
  end
end
