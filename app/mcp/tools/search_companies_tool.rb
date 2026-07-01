module Mcp
  module Tools
    class SearchCompaniesTool < BaseTool
      tool_name "search_companies"
      title "Search companies"
      description "Search the public TechIndex directory by name/description/location. Returns core fields and quality signals."
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, title: "Search companies")
      input_schema(
        properties: {
          query: { type: "string", description: "Free-text query matched against name, description, and location." },
          limit: { type: "integer", description: "Max results (1-25, default 10)." },
          needs_review: { type: "boolean", description: "Only return companies whose quality_status is needs_review." }
        },
        required: []
      )

      def self.call(server_context:, query: nil, limit: 10, needs_review: false)
        capped = [[limit.to_i, 1].max, 25].min
        scope = Company.publicly_visible.includes(:category, :secondary_category)
        scope = scope.needs_review if needs_review
        scope = scope.text_search(query) if query.present?
        companies = scope.order(:name).limit(capped)

        json_response(
          "query" => query,
          "count" => companies.size,
          "companies" => companies.map { |company| company_summary(company) }
        )
      end
    end
  end
end
