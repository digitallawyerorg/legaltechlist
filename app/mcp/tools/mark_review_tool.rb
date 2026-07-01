module Mcp
  module Tools
    class MarkReviewTool < BaseTool
      tool_name "mark_review"
      title "Mark company review"
      description "Record a human-style review decision on an existing company: verified, needs_work, or reject (reject also hides the company)."
      annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: true, title: "Mark company review")
      input_schema(
        properties: {
          slug: { type: "string", description: "Company slug or numeric id." },
          decision: { type: "string", enum: CompanyReviewMarkService::DECISIONS, description: "One of: #{CompanyReviewMarkService::DECISIONS.join(', ')}." }
        },
        required: ["slug", "decision"]
      )

      def self.call(server_context:, slug:, decision:)
        company = find_company(slug)
        return not_found("Company '#{slug}' not found") unless company
        unless CompanyReviewMarkService::DECISIONS.include?(decision.to_s)
          return not_found("Unknown decision '#{decision}'. Use one of: #{CompanyReviewMarkService::DECISIONS.join(', ')}")
        end

        CompanyReviewMarkService.call(company: company, decision: decision.to_s, admin_user: curator)
        company.reload

        audit!(action: "mark_review", summary: "Marked #{company.name} as #{decision}", records_processed: 1, details: { "company_id" => company.id, "decision" => decision })

        json_response(
          "company_slug" => company.slug,
          "decision" => decision,
          "quality_status" => company.quality_status,
          "verification_verdict" => company.verification_verdict,
          "visible" => company.visible
        )
      end
    end
  end
end
