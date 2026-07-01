module Mcp
  module Tools
    class RunCompanyReviewTool < BaseTool
      tool_name "run_company_review"
      title "Run company review"
      description "Run the agent evidence/verification/description review for an existing company. Writes findings to a pipeline run only; no public fields change. Returns safe proposed corrections you can apply with apply_safe_fields."
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false, title: "Run company review")
      input_schema(
        properties: {
          slug: { type: "string", description: "Company slug or numeric id." }
        },
        required: ["slug"]
      )

      def self.call(server_context:, slug:)
        company = find_company(slug)
        return not_found("Company '#{slug}' not found") unless company

        run = CompanyAgentReviewService.call(company: company, reviewer: "claude@techindex", notes: "Claude Tag curator review")
        details = run.details || {}
        corrections = details["proposed_corrections"] || {}

        json_response(
          "run_id" => run.id,
          "company_slug" => company.slug,
          "coordinator_status" => details.dig("review_coordinator", "status"),
          "safe_proposed_corrections" => corrections.slice(*ApplySafeFieldsTool::SAFE_FIELDS),
          "description_draft" => details.dig("description_draft", "proposed_description"),
          "risks" => details["risks"],
          "agent_review_url" => "#{Mcp::CuratorPolicy.site_url}/admin/agent-reviews/#{run.id}"
        )
      end
    end
  end
end
