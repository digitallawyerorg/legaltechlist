module Mcp
  module Tools
    class ListReviewQueueTool < BaseTool
      tool_name "list_review_queue"
      title "List review queue"
      description "List company proposals awaiting curation, with quality signals (publish_ready, score), duplicate flags and each row's website. Filter with `query` (name or website text) or `domain` (all rows on one domain, subdomains included) instead of paging the whole backlog. Defaults to open work only - the response says so, and reports whether your `limit` was capped."
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, title: "List review queue")
      input_schema(
        properties: {
          status: { type: "string", description: "Proposal status filter: pending, ready_for_review, needs_revision, approved_to_draft, published, rejected, or 'open' for the pending/ready/needs_revision group (default 'open')." },
          proposal_type: { type: "string", description: "Optional filter: atlas_candidate, discovery_candidate, user_contribution, user_suggestion." },
          limit: { type: "integer", description: "Max results per page (1-50, default 20)." },
          offset: { type: "integer", description: "Number of results to skip for paging through the full backlog (default 0). Use total to know how many pages remain." },
          query: { type: "string", description: "Free-text match against the candidate name and website." },
          domain: { type: "string", description: "Only rows whose website is on this domain, e.g. deep-law.com. Matches subdomains and ignores www." },
          exclude_reviewed: { type: "boolean", description: "Leave out proposals whose latest review is 'no_change' (already looked at and deliberately left as is). Each row reports last_review either way." }
        },
        required: []
      )

      def self.call(server_context:, status: "open", proposal_type: nil, limit: 20, offset: 0, query: nil, domain: nil, exclude_reviewed: false)
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
        scope = apply_text_filter(scope, query) if query.present?
        scope = apply_domain_filter(scope, domain) if domain.present?
        scope = exclude_reviewed_no_change(scope) if ActiveModel::Type::Boolean.new.cast(exclude_reviewed)
        total = scope.count
        proposals = scope.offset(skipped).limit(capped)

        json_response(
          "status" => status,
          "total" => total,
          "offset" => skipped,
          "limit" => capped,
          "limit_requested" => limit.to_i,
          "limit_capped" => capped < limit.to_i,
          "status_filter_note" => (status.to_s == "open" || status.blank?) ? "Showing open work only (pending, ready_for_review, needs_revision). Pass status to widen." : nil,
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
              # Without this a caller had to open every row to learn its domain.
              "main_url" => proposal.editable_changes["main_url"],
              "duplicate_blocking" => proposal.duplicate_blocking?,
              "publish_ready" => cached["publish_ready"],
              "quality_score" => cached["score"],
              "last_review" => proposal.latest_review,
              "last_review_label" => CompanyProposalReviewLog.label(proposal.latest_review),
              "admin_url" => admin_proposal_url(proposal)
            }
          end
        )
      end

      # Name and website, matched on the record as it currently stands rather than only
      # on its intake payload.
      def self.apply_text_filter(scope, query)
        needle = "%#{query.to_s.strip.downcase}%"
        scope.where(
          "LOWER(COALESCE(final_changes->>'name', proposed_changes->>'name', '')) LIKE :q OR " \
          "LOWER(COALESCE(final_changes->>'main_url', proposed_changes->>'main_url', '')) LIKE :q",
          q: needle
        )
      end

      def self.exclude_reviewed_no_change(scope)
        scope.where("(agent_details -> 'review_log' -> -1 ->> 'outcome') IS DISTINCT FROM ?", CompanyProposalReviewLog::OUTCOME_NO_CHANGE)
      end

      def self.apply_domain_filter(scope, domain)
        host = Company.canonical_domain_for(domain) || domain.to_s.strip.downcase.delete_prefix("www.")
        scope.where(
          "LOWER(COALESCE(final_changes->>'main_url', proposed_changes->>'main_url', '')) LIKE :exact OR " \
          "LOWER(COALESCE(final_changes->>'main_url', proposed_changes->>'main_url', '')) LIKE :sub",
          exact: "%//#{host}%", sub: "%.#{host}%"
        )
      end
    end
  end
end
