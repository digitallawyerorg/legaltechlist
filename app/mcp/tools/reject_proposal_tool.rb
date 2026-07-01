module Mcp
  module Tools
    class RejectProposalTool < BaseTool
      tool_name "reject_proposal"
      title "Reject proposal"
      description "Reject a proposal with a reason. The proposal is marked rejected and removed from the review queue."
      annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: false, title: "Reject proposal")
      input_schema(
        properties: {
          id: { type: "integer", description: "Proposal id." },
          reason: { type: "string", description: "Why the proposal is being rejected." }
        },
        required: ["id", "reason"]
      )

      def self.call(server_context:, id:, reason:)
        proposal = CompanyProposal.find_by(id: id)
        return not_found("Proposal #{id} not found") unless proposal
        return not_found("A rejection reason is required") if reason.to_s.strip.blank?

        proposal.update!(
          status: "rejected",
          rejection_reason: reason,
          rejected_at: Time.current,
          reviewed_at: Time.current,
          admin_user: curator
        )

        audit!(action: "reject_proposal", summary: "Rejected proposal #{id}", records_processed: 1, details: { "proposal_id" => id, "reason" => reason })

        json_response(
          "proposal_id" => proposal.id,
          "status" => proposal.status,
          "reason" => reason,
          "admin_url" => admin_proposal_url(proposal)
        )
      end
    end
  end
end
