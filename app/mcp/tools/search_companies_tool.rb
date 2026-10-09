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
          name_only: { type: "boolean", description: "Match query against the company name only (case-insensitive substring), e.g. to find sentence-fragment names like \"Our\" without every description that contains the word." },
          limit: { type: "integer", description: "Max results (1-25, default 10)." },
          needs_review: { type: "boolean", description: "Only return companies whose quality_status is needs_review." },
          missing_founded_date: { type: "boolean", description: "Only return companies with no founded_date set." },
          url_broken: { type: "boolean", description: "Only return companies whose website failed the health check (url_status=broken) — a soft signal to review for inactivity." },
          status: { type: "string", description: "Only return companies with this lifecycle status (e.g. \"acquired\", \"inactive\", \"active\"). Case-insensitive." }
        },
        required: []
      )

      def self.call(server_context:, query: nil, name_only: false, limit: 10, needs_review: false, missing_founded_date: false, url_broken: false, status: nil)
        capped = [[limit.to_i, 1].max, 25].min
        scope = Company.publicly_visible.includes(:category, :secondary_category)
        scope = scope.needs_review if needs_review
        scope = scope.missing_founded_date if missing_founded_date
        scope = scope.url_broken if url_broken
        scope = scope.where("LOWER(status) = ?", status.to_s.strip.downcase) if status.present?
        if query.present? && ActiveModel::Type::Boolean.new.cast(name_only)
          scope = scope.where("companies.name ILIKE ?", "%#{Company.sanitize_sql_like(query.to_s.strip)}%")
        elsif query.present?
          scope = scope.text_search(query)
        end
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
