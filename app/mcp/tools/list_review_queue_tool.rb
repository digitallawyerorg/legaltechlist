module Mcp
  module Tools
    class ListReviewQueueTool < BaseTool
      tool_name "list_review_queue"
      title "List review queue"
      description "List company proposals awaiting curation, with quality signals (publish_ready, score) and duplicate flags. Quality is computed live when not yet cached, so publish_ready is always populated."
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, title: "List review queue")
      input_schema(
        properties: {
          status: { type: "string", description: "Proposal status filter: pending, ready_for_review, needs_revision, approved_to_draft, published, rejected, or 'open' for the pending/ready/needs_revision group (default 'open')." },
          proposal_type: { type: "string", description: "Optional filter: atlas_candidate, discovery_candidate, user_contribution, user_suggestion." },
          limit: { type: "integer", description: "Max results per page (1-50, default 20)." },
          offset: { type: "integer", description: "Number of results to skip for paging through the full backlog (default 0). Use total to know how many pages remain." }
        },
        required: []
      )

      def self.call(server_context:, status: "open", proposal_type: nil, limit: 20, offset: 0)
        capped = [[limit.to_i, 1].max, 50].min
        skipped = [offset.to_i, 0].max
        scope = CompanyProposal.recent
        scope = if status.to_s == "open" || status.blank?
          scope.pending_review
        elsif CompanyProposal::STATUSES.include?(status.to_s)
          scope.where(status: status.to_s)
        else
          return not_found("Unknown status '#{status}'. Use one of: open, #{CompanyProposal::STATUSES.join(', ')}")
        end
        scope = scope.where(proposal_type: proposal_type.to_s) if proposal_type.present?
        total = scope.count
        proposals = scope.offset(skipped).limit(capped)

        json_response(
          "status" => status,
          "total" => total,
          "offset" => skipped,
          "limit" => capped,
          "returned" => proposals.size,
          "has_more" => (skipped + proposals.size) < total,
          "count" => proposals.size,
          "proposals" => proposals.map do |proposal|
            # Fall back to a live quality read when the cached report has not been
            # materialized yet (freshly-committed proposals) so publish_ready is never null.
            cached = proposal.cached_quality_report.presence || CompanyProposalQualityService.call(proposal)
            {
              "id" => proposal.id,
              "name" => proposal.display_name,
              "status" => proposal.status,
              "proposal_type" => proposal.proposal_type,
              "source" => proposal.source,
              "created_at" => proposal.created_at.iso8601,
              "duplicate_blocking" => proposal.duplicate_blocking?,
              "publish_ready" => cached["publish_ready"],
              "quality_score" => cached["score"],
              "admin_url" => admin_proposal_url(proposal)
            }
          end
        )
      end
    end
  end
end
