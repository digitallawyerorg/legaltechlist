module Mcp
  module Tools
    # Enqueues asynchronous, server-side founded_date backfills across companies
    # whose founded_date is blank. Each job runs the same cite-only + same-entity
    # guards as proposal enrichment and only writes a year a real source states.
    class BackfillFoundedDatesTool < BaseTool
      tool_name "backfill_founded_dates"
      title "Backfill founded_date on companies"
      description "Enqueue asynchronous server-side founded_date backfills. Each job runs a targeted founding-year web search with the same cite-only + same-entity guards as proposal enrichment and only writes a year a real source states. A blind run (limit) selects only companies that are still blank AND have not been attempted in the last ~3 days, so re-runs reach untried companies instead of re-researching known no-source ones. Pass company_ids to target specific companies (e.g. newly-published ones), which bypasses the cooldown. Poll get_company to observe results."
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false, title: "Backfill founded_date on companies")
      input_schema(
        properties: {
          limit: { type: "integer", description: "Blind-sweep size (1-50, default 10). Ignored when company_ids is given. Only picks companies not attempted within the ~3-day cooldown." },
          company_ids: { type: "array", items: { type: "integer" }, description: "Optional: target these specific company ids (still limited to those with a blank founded_date). Bypasses the re-attempt cooldown for explicit targeting." }
        },
        required: []
      )

      def self.call(server_context:, limit: 10, company_ids: nil)
        targeted = Array(company_ids).map(&:to_i).reject(&:zero?)

        if targeted.any?
          selected = Company.missing_founded_date.where(id: targeted).pluck(:id)
          force = true
        else
          capped = [[limit.to_i, 1].max, 50].min
          selected = Company.founded_date_backfill_due(CompanyFoundedDateBackfillService::RE_ATTEMPT_COOLDOWN).order(:id).limit(capped).pluck(:id)
          force = false
        end

        selected.each { |id| BackfillFoundedDateJob.perform_later(id, curator.id, force) }

        audit!(action: "backfill_founded_dates", summary: "Enqueued #{selected.size} founded_date backfills#{' (targeted)' if targeted.any?}", records_processed: selected.size, details: { "company_ids" => selected, "targeted" => targeted.any? })

        json_response("result" => "enqueued", "enqueued" => selected.size, "company_ids" => selected, "targeted" => targeted.any?, "cooldown_days" => (CompanyFoundedDateBackfillService::RE_ATTEMPT_COOLDOWN / 1.day).to_i)
      end
    end
  end
end
