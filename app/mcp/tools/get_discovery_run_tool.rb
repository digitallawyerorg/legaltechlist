module Mcp
  module Tools
    class GetDiscoveryRunTool < BaseTool
      tool_name "get_discovery_run"
      title "Get discovery run"
      description "Fetch the status and results of an async discover_companies run. Poll after discover_companies: status is pending/running while it works, then succeeded (results attached: summary, queued proposal ids, candidate preview) or failed (error attached)."
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, title: "Get discovery run")
      input_schema(
        properties: {
          run_id: { type: "integer", description: "The run_id returned by discover_companies." }
        },
        required: ["run_id"]
      )

      def self.call(server_context:, run_id:)
        run = PipelineRun.find_by(id: run_id, run_type: CompanyDiscoveryService::RUN_TYPE)
        return not_found("Discovery run #{run_id} not found") unless run

        details = run.details || {}
        payload = {
          "run_id" => run.id,
          "status" => run.status,
          "discovery_type" => details["discovery_type"],
          "dry_run" => details["dry_run"],
          "created_at" => run.created_at.iso8601,
          "started_at" => run.started_at&.iso8601,
          "finished_at" => run.finished_at&.iso8601
        }

        case run.status
        when "succeeded"
          proposal_results = Array(details["proposal_results"])
          payload.merge!(
            "result" => "succeeded",
            "summary" => details["summary"],
            "records_processed" => run.records_processed,
            "queued_proposals_count" => proposal_results.size,
            "queued_proposal_ids" => proposal_results.filter_map { |result| result["proposal_id"] },
            "candidates_preview" => Array(details["candidates"]).first(20).map { |candidate| candidate.slice("name", "website", "status") }
          )
        when "failed"
          payload.merge!(
            "result" => "failed",
            "retryable" => true,
            "error" => run.error_message.presence || details["error_class"]
          )
        else
          payload["result"] = "pending"
          payload["poll"] = "Still running; call get_discovery_run(#{run.id}) again in a few seconds."
        end

        json_response(payload)
      end
    end
  end
end
