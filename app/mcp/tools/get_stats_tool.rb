module Mcp
  module Tools
    class GetStatsTool < BaseTool
      tool_name "get_stats"
      title "Get stats"
      description "Read-only directory and backlog metrics for cadence planning: company totals and data-quality gaps, proposal counts by status and type, pipeline run counts, and the current curator autonomy settings. Company metrics are cached (~10 min)."
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, title: "Get stats")
      input_schema(properties: {}, required: [])

      def self.call(server_context:)
        metrics = AdminDashboardMetrics.load
        summary = (metrics[:company_summary_counts] || {})

        json_response(
          "companies" => {
            "total" => summary[:total],
            "visible" => summary[:visible],
            "hidden" => summary[:hidden],
            "needs_review" => summary[:needs_review],
            "not_reviewed" => summary[:not_reviewed],
            "missing_url" => summary[:missing_url],
            "weak_description" => summary[:weak_description],
            "unknown_taxonomy" => summary[:unknown_taxonomy],
            "duplicate_domain_candidates" => summary[:duplicate_domain],
            "duplicate_name_candidates" => summary[:duplicate_name]
          },
          "proposals" => {
            "by_status" => CompanyProposal.group(:status).count,
            "by_type" => CompanyProposal.group(:proposal_type).count,
            "pending_review" => CompanyProposal.pending_review.count
          },
          "pipeline_runs" => {
            "total" => metrics[:pipeline_run_count],
            "failed" => metrics[:failed_pipeline_run_count]
          },
          "curator" => {
            "autopublish_enabled" => Mcp::CuratorPolicy.autopublish_enabled?,
            "autoapply_updates_enabled" => Mcp::CuratorPolicy.autoapply_updates_enabled?,
            "min_confidence" => Mcp::CuratorPolicy.min_confidence,
            "published_today" => Mcp::CuratorPolicy.published_today(curator),
            "remaining_daily_publish_budget" => Mcp::CuratorPolicy.remaining_daily_publish_budget(curator)
          }
        )
      end
    end
  end
end
