module Mcp
  module Tools
    class GetProposalTool < BaseTool
      tool_name "get_proposal"
      title "Get proposal"
      description "Fetch a single company proposal with proposed/final changes, a fresh quality report, and duplicate signals."
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, title: "Get proposal")
      input_schema(
        properties: {
          id: { type: "integer", description: "Proposal id." }
        },
        required: ["id"]
      )

      def self.call(server_context:, id:)
        proposal = CompanyProposal.find_by(id: id)
        return not_found("Proposal #{id} not found") unless proposal

        json_response(
          "id" => proposal.id,
          "name" => proposal.display_name,
          "status" => proposal.status,
          "proposal_type" => proposal.proposal_type,
          "source" => proposal.source,
          "created_at" => proposal.created_at.iso8601,
          "editable_changes" => proposal.editable_changes,
          "final_changes" => proposal.final_changes,
          "duplicate_signals" => proposal.duplicate_signals,
          "duplicate_blocking" => proposal.duplicate_blocking?,
          "enriched_at" => proposal.enriched_at&.iso8601,
          "enrichment_error" => proposal.agent_details["enrichment_error"],
          "founded_date_source" => proposal.agent_details["founded_date_source"],
          "quality" => CompanyProposalQualityService.call(proposal),
          "admin_url" => admin_proposal_url(proposal)
        )
      end
    end
  end
end
