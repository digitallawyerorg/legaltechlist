module Mcp
  module Tools
    # Enqueues asynchronous website health probes across companies. Each job fetches
    # the company's main_url and records a coarse verdict (ok / unknown / broken) used
    # as a QC/maintenance signal for spotting companies that may have gone inactive.
    # It never changes lifecycle status — a broken URL is a soft indicator to review.
    class CheckUrlHealthTool < BaseTool
      tool_name "check_url_health"
      title "Check company website health"
      description "Enqueue asynchronous website reachability checks. Each job fetches a company's main_url (following redirects, with a bot-block/transient-failure allowance) and records url_status = ok, unknown (up but access-restricted or a single transient failure), or broken (gone/unreachable across consecutive checks). A broken URL is a SOFT signal that a company may be inactive — verify before changing status; use update_company_field(status) or record_acquisition to actually update lifecycle. A blind run (limit) selects companies believed active that have not been checked within the ~30-day cooldown; pass company_ids to target specific companies. Returns an enqueue summary right away (checks run async, not inline): result:\"enqueued\", enqueued (count), company_ids (those queued), skipped + skipped_company_ids (requested ids that were unknown or had no main_url), and targeted. Per-URL verdicts land later: poll get_company for the recorded url_status + reason_code, list them with list_companies(url_health_status:\"broken\"|\"ok\"|\"untried\", optionally url_reason:\"dns_failure\"|\"bot_blocked\"|...) or search_companies(url_broken:true), and track totals with get_stats.companies.url_health (ok/broken/unknown/untried/last_run_at plus by_reason). Each verdict carries a reason_code (bot_blocked/tls_untrusted = usually live; dns_failure/http_404/http_410/connection_reset = likely dead; offsite_redirect = lands on another brand domain (rebrand, acquirer or lapsed domain: check it); suspected_hijack = lands on a gambling/spam site (broken at once: clear the URL or hide the record)) so an \"unknown\" isn't left in limbo. HTTP client errors use one code per status (http_404, http_400, ...); read the live set from get_stats.companies.url_health.by_reason."
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false, title: "Check company website health")
      input_schema(
        properties: {
          limit: { type: "integer", description: "Blind-sweep size (1-200, default 50). Ignored when company_ids is given. Only picks active companies not checked within the ~30-day cooldown." },
          company_ids: { type: "array", items: { type: "integer" }, description: "Optional: check these specific company ids now (bypasses the cooldown; only those with a main_url are enqueued)." }
        },
        required: []
      )

      def self.call(server_context:, limit: 50, company_ids: nil)
        targeted = Array(company_ids).map(&:to_i).reject(&:zero?)

        if targeted.any?
          selected = Company.with_main_url.where(id: targeted).pluck(:id)
          # Requested ids we couldn't enqueue (unknown id or no main_url) so the caller
          # gets an honest run summary rather than assuming every id was queued.
          skipped = targeted - selected
        else
          capped = [[limit.to_i, 1].max, 200].min
          selected = Company.url_check_due.order(Arel.sql("url_checked_at ASC NULLS FIRST")).limit(capped).pluck(:id)
          skipped = []
        end

        selected.each { |id| CheckCompanyUrlHealthJob.perform_later(id) }

        audit!(action: "check_url_health", summary: "Enqueued #{selected.size} URL health checks#{' (targeted)' if targeted.any?}", records_processed: selected.size, details: { "company_ids" => selected, "skipped" => skipped, "targeted" => targeted.any? })

        json_response(
          "result" => "enqueued",
          "enqueued" => selected.size,
          "skipped" => skipped.size,
          "skipped_company_ids" => skipped,
          "company_ids" => selected,
          "targeted" => targeted.any?,
          "note" => "Checks run asynchronously; read per-URL verdicts via get_company or list_companies(url_health_status: \"broken\") once jobs drain, and track totals with get_stats companies.url_health."
        )
      end
    end
  end
end
