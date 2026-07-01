# Tiered curation loop for pending proposals, mirroring scripts/discovery_batch.rb:
# enrich -> assess quality -> auto-publish only when the proposal passes the quality
# gate and has no duplicate signals; otherwise leave it for human approval. Discovery
# candidates flagged as nonprofit/advocacy are rejected.
class CuratorPendingService
  DISCOVERY_SOURCE = CompanyDiscoveryService::SOURCE
  DISCOVERY_PROPOSAL_TYPE = CompanyDiscoveryService::PROPOSAL_TYPE
  MAX_SINCE_MINUTES = 7 * 24 * 60

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(admin_user:, since_minutes: 60, limit: 25, source: nil, publish: true)
    @admin_user = admin_user
    @since_minutes = since_minutes.to_i.clamp(1, MAX_SINCE_MINUTES)
    @limit = limit.to_i.clamp(1, Mcp::CuratorPolicy.max_curate_limit)
    @source = source.presence
    @publish = ActiveModel::Type::Boolean.new.cast(publish)
  end

  def call
    published = []
    queued = []
    rejected = []
    budget = Mcp::CuratorPolicy.remaining_daily_publish_budget(admin_user)

    proposals.each do |proposal|
      begin
        if discovery_candidate?(proposal) && nonprofit_rejected?(proposal)
          reject!(proposal, "Nonprofit/advocacy organization outside index scope.")
          rejected << outcome(proposal, reason: "nonprofit_advocacy")
          next
        end

        enrich!(proposal)
        proposal.reload
        quality = CompanyProposalQualityService.call(proposal)

        if proposal.duplicate_blocking?
          queued << outcome(proposal, reason: "duplicate_signals", blockers: quality["blockers"])
          next
        end

        if can_autopublish?(quality, budget)
          CompanyProposalApprovalService.call(proposal: proposal, admin_user: admin_user, publish: true)
          budget -= 1
          published << outcome(proposal.reload)
        else
          queued << outcome(proposal, reason: skip_reason(quality, budget), blockers: quality["blockers"])
        end
      rescue StandardError => e
        queued << outcome(proposal, reason: "error", blockers: [e.message])
      end
    end

    {
      "scanned" => published.size + queued.size + rejected.size,
      "published" => published,
      "queued_for_review" => queued,
      "rejected" => rejected,
      "remaining_daily_publish_budget" => budget,
      "autopublish_enabled" => Mcp::CuratorPolicy.autopublish_enabled?
    }
  end

  private

  attr_reader :admin_user, :since_minutes, :limit, :source, :publish

  def proposals
    scope = CompanyProposal.where(status: %w[pending ready_for_review])
                           .where("created_at >= ?", since_minutes.minutes.ago)
                           .order(:created_at)
                           .limit(limit)
    scope = scope.where(source: source) if source
    scope.to_a
  end

  def can_autopublish?(quality, budget)
    publish && Mcp::CuratorPolicy.autopublish_enabled? && quality["publish_ready"] && budget.positive?
  end

  def skip_reason(quality, budget)
    return "publish_disabled_by_request" unless publish
    return "autopublish_kill_switch" unless Mcp::CuratorPolicy.autopublish_enabled?
    return "quality_gate" unless quality["publish_ready"]
    return "daily_publish_budget_exhausted" unless budget.positive?

    "needs_review"
  end

  def enrich!(proposal)
    CompanyProposalEnrichmentService.call(proposal: proposal, admin_user: admin_user)
  rescue StandardError => e
    Rails.logger.debug("[CuratorPendingService] enrich failed for proposal #{proposal.id}: #{e.message}")
  end

  def discovery_candidate?(proposal)
    proposal.proposal_type == DISCOVERY_PROPOSAL_TYPE || proposal.source == DISCOVERY_SOURCE
  end

  def nonprofit_rejected?(proposal)
    return false unless defined?(DiscoveryNonprofitAdvocacyFilter)

    candidate = (proposal.source_payload || {}).merge(
      "name" => proposal.proposed_changes["name"],
      "website" => proposal.proposed_changes["main_url"],
      "description" => proposal.final_changes["description"]
    )
    DiscoveryNonprofitAdvocacyFilter.rejected?(candidate)
  rescue StandardError
    false
  end

  def reject!(proposal, reason)
    proposal.update!(
      status: "rejected",
      rejection_reason: reason,
      rejected_at: Time.current,
      reviewed_at: Time.current,
      admin_user: admin_user
    )
  end

  def outcome(proposal, reason: nil, blockers: nil)
    {
      "id" => proposal.id,
      "name" => proposal.display_name,
      "status" => proposal.status,
      "reason" => reason,
      "blockers" => blockers.presence,
      "admin_url" => SlackNotifier.admin_proposal_url(proposal)
    }.compact
  end
end
