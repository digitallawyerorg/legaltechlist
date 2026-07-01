module Mcp
  module Tools
    class AssessProposalTool < BaseTool
      tool_name "assess_proposal"
      title "Assess proposal"
      description "Return the deterministic quality report for a proposal (score, publish_ready, blockers, warnings) without changing it."
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, title: "Assess proposal")
      input_schema(
        properties: {
          id: { type: "integer", description: "Proposal id." }
        },
        required: ["id"]
      )

      def self.call(server_context:, id:)
        proposal = CompanyProposal.find_by(id: id)
        return not_found("Proposal #{id} not found") unless proposal

        quality = CompanyProposalQualityService.call(proposal)
        json_response(
          "proposal_id" => proposal.id,
          "status" => proposal.status,
          "duplicate_blocking" => proposal.duplicate_blocking?,
          "publish_ready" => quality["publish_ready"] && !proposal.duplicate_blocking?,
          "quality" => quality,
          "admin_url" => admin_proposal_url(proposal)
        )
      end
    end
  end
end
