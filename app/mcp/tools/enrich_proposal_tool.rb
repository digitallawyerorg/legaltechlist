module Mcp
  module Tools
    class EnrichProposalTool < BaseTool
      tool_name "enrich_proposal"
      title "Enrich proposal"
      description "Run description + taxonomy enrichment on a proposal and return the refreshed quality report."
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

        CompanyProposalEnrichmentService.call(proposal: proposal, admin_user: curator)
        proposal.reload
        quality = CompanyProposalQualityService.call(proposal)

        audit!(action: "enrich_proposal", summary: "Enriched proposal #{id}", records_processed: 1, details: { "proposal_id" => id, "publish_ready" => quality["publish_ready"] })

        json_response(
          "proposal_id" => proposal.id,
          "status" => proposal.status,
          "quality" => quality,
          "duplicate_blocking" => proposal.duplicate_blocking?,
          "admin_url" => admin_proposal_url(proposal)
        )
      end
    end
  end
end
