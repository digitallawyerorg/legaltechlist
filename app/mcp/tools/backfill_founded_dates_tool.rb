module Mcp
  module Tools
    # Enqueues asynchronous, server-side founded_date backfills across companies
    # whose founded_date is blank. Each job runs the same cite-only + same-entity
    # guards as proposal enrichment and only writes a year a real source states.
    class BackfillFoundedDatesTool < BaseTool
      tool_name "backfill_founded_dates"
      title "Backfill founded_date on companies"
      description "Enqueue N asynchronous server-side founded_date backfills across companies where founded_date is blank. Each job runs the same cite-only guard used by proposal enrichment and only writes a year when a real source states it. Poll get_company to observe results."
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false, title: "Backfill founded_date on companies")
      input_schema(
        properties: {
          limit: { type: "integer", description: "How many companies to enqueue (1-50, default 10)." }
        },
        required: []
      )

      def self.call(server_context:, limit: 10)
        capped = [[limit.to_i, 1].max, 50].min
        company_ids = Company.missing_founded_date.limit(capped).pluck(:id)
        company_ids.each { |id| BackfillFoundedDateJob.perform_later(id, curator.id) }

        audit!(action: "backfill_founded_dates", summary: "Enqueued #{company_ids.size} founded_date backfills", records_processed: company_ids.size, details: { "company_ids" => company_ids })

        json_response("result" => "enqueued", "enqueued" => company_ids.size, "company_ids" => company_ids)
      end
    end
  end
end
