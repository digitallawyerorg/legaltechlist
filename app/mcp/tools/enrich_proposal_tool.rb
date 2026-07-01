module Mcp
  module Tools
    class EnrichProposalTool < BaseTool
      tool_name "enrich_proposal"
      title "Enrich proposal"
      description "Queue asynchronous server-side enrichment (web-grounded description, taxonomy suggestion, and a strictly-sourced founding year) for a proposal, then poll get_proposal until it completes. Runs off the request thread so it is not limited by the HTTP timeout. Enrichment only fills founded_date when a real source states it — it never guesses. If you already have web research and a draft, prefer writing fields directly with update_proposal (faster, synchronous)."
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false, title: "Enrich proposal")
      # Skip a re-enrich when the item was enriched this recently and gained nothing —
      # re-running rarely produces new facts and just burns web-search/LLM cost.
      RE_ENRICH_COOLDOWN = 3.days

      input_schema(
        properties: {
          id: { type: "integer", description: "Proposal id." },
          force: { type: "boolean", description: "Re-enrich even if the proposal is already publishable or was enriched recently. Default false. Use after sourcing improvements to intentionally refresh." }
        },
        required: ["id"]
      )

      def self.call(server_context:, id:, force: false)
        proposal = CompanyProposal.find_by(id: id)
        return not_found("Proposal #{id} not found") unless proposal

        force = ActiveModel::Type::Boolean.new.cast(force)

        unless force
          quality = CompanyProposalQualityService.call(proposal)
          if quality["publish_ready"]
            return json_response("result" => "skipped_already_publishable", "proposal_id" => proposal.id, "note" => "Already passes the quality gate; enrichment skipped. Pass force=true to enrich anyway.", "quality" => quality, "admin_url" => admin_proposal_url(proposal))
          end
          if proposal.enriched_at.present? && proposal.enriched_at > RE_ENRICH_COOLDOWN.ago
            return json_response("result" => "skipped_recently_enriched", "proposal_id" => proposal.id, "enriched_at" => proposal.enriched_at.iso8601, "note" => "Enriched within the last #{RE_ENRICH_COOLDOWN.inspect}; re-enriching rarely adds facts. Pass force=true to override, or set fields directly with update_proposal.", "admin_url" => admin_proposal_url(proposal))
          end
        end

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
