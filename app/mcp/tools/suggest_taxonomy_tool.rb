module Mcp
  module Tools
    class SuggestTaxonomyTool < BaseTool
      tool_name "suggest_taxonomy"
      title "Suggest taxonomy"
      description "Suggest primary/secondary category, revenue models, target clients, and tags for an existing company. Read-only: returns a suggestion without changing the company."
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, title: "Suggest taxonomy")
      input_schema(
        properties: {
          slug: { type: "string", description: "Company slug or numeric id." }
        },
        required: ["slug"]
      )

      def self.call(server_context:, slug:)
        company = find_company(slug)
        return not_found("Company '#{slug}' not found") unless company

        source_payload = {
          "name" => company.name,
          "website" => company.main_url,
          "source_description" => company.description,
          "industries" => company.tags.map(&:name),
          "location" => company.location,
          "founded_date" => company.founded_date
        }
        suggestion = CompanyProposalTaxonomySuggestionService.call(source_payload: source_payload, final_changes: {})

        json_response("company_slug" => company.slug, "suggestion" => suggestion)
      end
    end
  end
end
