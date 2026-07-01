module Mcp
  module Tools
    class CuratePendingTool < BaseTool
      tool_name "curate_pending"
      title "Curate pending proposals"
      description "Tiered curation of pending proposals: enrich, assess, auto-publish only high-confidence entries that pass the quality gate and have no duplicate signals; everything else is left for human approval. Respects the auto-publish kill-switch and the daily publish budget."
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false, title: "Curate pending proposals")
      input_schema(
        properties: {
          since_minutes: { type: "integer", description: "Only consider proposals created within this many minutes (default 60)." },
          limit: { type: "integer", description: "Max proposals to process (capped by MCP_CURATOR_MAX_CURATE_LIMIT)." },
          source: { type: "string", description: "Optional source filter, e.g. llm_discovery." },
          publish: { type: "boolean", description: "If false, only enrich and assess (never publish). Default true." }
        },
        required: []
      )

      def self.call(server_context:, since_minutes: 60, limit: 25, source: nil, publish: true)
        result = CuratorPendingService.call(
          admin_user: curator,
          since_minutes: since_minutes,
          limit: limit,
          source: source,
          publish: publish
        )

        audit!(
          action: "curate_pending",
          summary: "Published #{result['published'].size}, queued #{result['queued_for_review'].size}, rejected #{result['rejected'].size}",
          records_processed: result["scanned"],
          details: result
        )

        SlackNotifier.curator_summary(result) if Mcp::CuratorPolicy.slack_summary_enabled?

        json_response(result)
      end
    end
  end
end
