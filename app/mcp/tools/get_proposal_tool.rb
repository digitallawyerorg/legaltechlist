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

        quality = CompanyProposalQualityService.call(proposal)

        json_response(
          "id" => proposal.id,
          "name" => proposal.display_name,
          "status" => proposal.status,
          "proposal_type" => proposal.proposal_type,
          "source" => proposal.source,
          "created_at" => proposal.created_at.iso8601,
          "editable_changes" => proposal.editable_changes,
          "final_changes" => proposal.final_changes,
          # Resolved now, not read from the stored column. The two disagreed: the column
          # is only rewritten when a record is opened or enriched, so a proposal could
          # report empty signals beside duplicate_blocking=true (or the reverse), and a
          # reader taking either one on its own drew the wrong conclusion. duplicate_evidence
          # is the append-only record of what the guard saw, which the live view forgets
          # once a matched record changes state.
          "duplicate_signals" => proposal.current_duplicate_signals,
          "duplicate_blocking" => proposal.duplicate_blocking?,
          "duplicate_evidence" => proposal.duplicate_evidence,
          # The approval record. These columns always existed; none of them were exposed,
          # so an agent could not tell an approved record from an unapproved one, nor see
          # whose decision it was reading.
          "approval" => {
            "approved_at" => proposal.approved_at&.iso8601,
            "reviewed_at" => proposal.reviewed_at&.iso8601,
            "rejected_at" => proposal.rejected_at&.iso8601,
            "rejection_reason" => proposal.rejection_reason,
            "admin_user" => proposal.admin_user&.email,
            "company_id" => proposal.company_id,
            "company_visible" => proposal.company&.visible,
            "canonical_record" => proposal.agent_details["canonical_record"]
          },
          # Who sent it in, and what they said. Also always present, also unexposed.
          "submitter" => {
            "email" => proposal.submitter_email.presence,
            "name" => proposal.submitter_name.presence,
            "message" => proposal.user_message.presence,
            "issue_type" => proposal.issue_type.presence
          },
          # What automated processing is allowed to do to this record.
          "automation" => {
            "do_not_enrich" => proposal.agent_details["do_not_enrich"] == true,
            "do_not_enrich_reason" => proposal.agent_details["do_not_enrich_reason"],
            "description_locked" => proposal.company&.quality_review.is_a?(Hash) && proposal.company.quality_review["description_locked"] == true,
            "enrichment_skipped" => proposal.agent_details["enrichment_skipped"]
          },
          # Wording an automated pass replaced, newest first, so a restore is a lookup.
          "description_history" => Array(proposal.agent_details["description_history"]).reverse,
          "description_verification" => proposal.agent_details["description_verification"],
          "enriched_at" => proposal.enriched_at&.iso8601,
          "enrichment_error" => proposal.agent_details["enrichment_error"],
          "founded_date_source" => proposal.agent_details["founded_date_source"],
          # Surface the LIVE critic verdict (computed on the current description),
          # so it always agrees with the publish gate rather than a stale stored one.
          "description_critic" => quality["description_critic"],
          "taxonomy_suggestion" => proposal.agent_details["taxonomy_suggestion"],
          "quality" => quality,
          "admin_url" => admin_proposal_url(proposal)
        )
      end
    end
  end
end
