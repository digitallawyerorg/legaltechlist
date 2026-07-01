class EnrichProposalJob < ApplicationJob
  queue_as :default

  # Runs proposal enrichment off the request thread so it is not bound by the
  # 30s HTTP router timeout. On success the enrichment service stamps enriched_at
  # (the completion signal callers poll for); on failure we record an
  # enrichment_error marker on agent_details so pollers can detect it.
  def perform(proposal_id, admin_user_id = nil)
    proposal = CompanyProposal.find_by(id: proposal_id)
    return unless proposal

    admin_user = AdminUser.find_by(id: admin_user_id) || Mcp::CuratorActor.admin_user!
    CompanyProposalEnrichmentService.call(proposal: proposal, admin_user: admin_user)
  rescue StandardError => e
    Rails.logger.debug("[EnrichProposalJob] enrichment failed for proposal #{proposal_id}: #{e.message}")
    proposal&.update_columns(
      agent_details: (proposal.agent_details || {}).merge(
        "enrichment_error" => { "message" => e.message, "failed_at" => Time.current.utc.iso8601 }
      )
    )
  end
end
