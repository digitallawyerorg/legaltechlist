module Mcp
  module Tools
    class RecordProposalReviewTool < BaseTool
      tool_name "record_proposal_review"
      title "Record proposal review"
      description "Record that a proposal was reviewed, without approving or rejecting it: `no_change` (looked at it, nothing to change, leave it as it is) or `needs_more_work` (requires a note saying what is missing; moves the proposal to needs_revision). The entry (outcome, reviewer, date, note) is kept in the proposal's review_log, shown by get_proposal and as last_review in list_review_queue, so a reviewed proposal is not triaged again. Changes no company data. Rejected and published proposals are closed and cannot be reviewed."
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false, title: "Record proposal review")
      input_schema(
        properties: {
          id: { type: "integer", description: "Proposal id." },
          outcome: { type: "string", enum: CompanyProposalReviewLog::RECORDABLE_OUTCOMES, description: "no_change or needs_more_work." },
          note: { type: "string", description: "What you checked, or what still needs doing. Required for needs_more_work." }
        },
        required: ["id", "outcome"]
      )

      def self.call(server_context:, id:, outcome:, note: nil)
        proposal = CompanyProposal.find_by(id: id)
        return not_found("Proposal #{id} not found") unless proposal
        unless CompanyProposalReviewLog::RECORDABLE_OUTCOMES.include?(outcome.to_s)
          return error_response("result" => "blocked", "retryable" => false, "error" => "outcome must be one of: #{CompanyProposalReviewLog::RECORDABLE_OUTCOMES.join(', ')}")
        end

        reviewer = Mcp::Current.operator_email.presence || curator.email
        entry = CompanyProposalReviewLog.record!(proposal, outcome: outcome.to_s, reviewer: reviewer, note: note, via: "mcp")
        audit!(action: "record_proposal_review", summary: "#{CompanyProposalReviewLog.label(entry)} on proposal #{proposal.id}", records_processed: 1,
               details: { "proposal_id" => proposal.id, "outcome" => outcome.to_s, "note" => entry["note"] })

        json_response(
          "id" => proposal.id,
          "status" => proposal.reload.status,
          "review" => entry,
          "label" => CompanyProposalReviewLog.label(entry),
          "admin_url" => admin_proposal_url(proposal)
        )
      rescue ArgumentError => e
        error_response("result" => "blocked", "retryable" => false, "error" => e.message)
      end
    end
  end
end
