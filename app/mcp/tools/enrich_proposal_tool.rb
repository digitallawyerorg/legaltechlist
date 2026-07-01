module Mcp
  module Tools
    class EnrichProposalTool < BaseTool
      tool_name "enrich_proposal"
      title "Enrich proposal"
      description "Queue asynchronous server-side enrichment (web-grounded description, taxonomy suggestion, and a strictly-sourced founding year) for a proposal, then poll get_proposal until it completes. Runs off the request thread so it is not limited by the HTTP timeout. Enrichment only fills founded_date when a real source states it — it never guesses. If you already have web research and a draft, prefer writing fields directly with update_proposal (faster, synchronous)."
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false, title: "Enrich proposal")
      input_schema(
        properties: {
          id: { type: "integer", description: "Proposal id." }
        },
        required: ["id"]
      )

      def self.call(server_context:, id:)
        proposal = CompanyProposal.find_by(id: id)
        return not_found("Proposal #{id} not found") unless proposal

        proposal.update_columns(agent_details: proposal.agent_details.except("enrichment_error")) if proposal.agent_details["enrichment_error"].present?
        EnrichProposalJob.perform_later(proposal.id, curator.id)

        audit!(action: "enrich_proposal", summary: "Queued enrichment for proposal #{id}", records_processed: 1, details: { "proposal_id" => id })

        json_response(
          "result" => "enrichment_queued",
          "proposal_id" => proposal.id,
          "status" => proposal.status,
          "enriched_at_before" => proposal.enriched_at&.iso8601,
          "poll" => "Call get_proposal(#{id}) until enriched_at is newer than enriched_at_before (success) or agent_details.enrichment_error appears (failure). Enrichment usually takes 20-60s.",
          "admin_url" => admin_proposal_url(proposal)
        )
      end
    end
  end
end
