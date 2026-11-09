module Mcp
  module Tools
    class SearchCompaniesTool < BaseTool
      tool_name "search_companies"
      title "Search companies"
      description "Search the public TechIndex directory by name/description/location. Returns core fields and quality signals. A free-text query is a substring search, so it also returns records that merely contain the text (in a longer name, the description or the location): each result says how its name relates to the query in `name_match` (exact, same_core, partial, or none), and exact and same-core names are listed first. Only exact and same_core indicate the same company name; use duplicate_check to decide whether a candidate is a duplicate."
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

      NAME_MATCH_RANK = { "exact" => 0, "same_core" => 1, "partial" => 2, "none" => 3 }.freeze

      # How the company's name relates to the query, so a hit that only shares a fragment
      # ("Ligi" inside "Eligible Legal") is not read as the same company.
      def self.name_match(query, name)
        normalized_query = Company.normalized_name_value(query)
        normalized_name = Company.normalized_name_value(name)
        return "none" if normalized_query.blank? || normalized_name.blank?
        return "exact" if normalized_query == normalized_name

        query_core = CompanyIdentityMatcher.core_key(query)
        return "same_core" if query_core.present? && query_core == CompanyIdentityMatcher.core_key(name)
        return "partial" if normalized_name.delete(" ").include?(normalized_query.delete(" "))

        "none"
      end

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
        companies = if query.present?
          # Fetch a wider window, then put real name matches ahead of incidental substring
          # hits, which would otherwise crowd them out of an alphabetical page.
          scope.order(:name).limit([capped * 4, 100].min).to_a
               .sort_by.with_index { |company, index| [NAME_MATCH_RANK.fetch(name_match(query, company.name)), index] }
               .first(capped)
        else
          scope.order(:name).limit(capped).to_a
        end

        json_response(
          "query" => query,
          "count" => companies.size,
          "companies" => companies.map do |company|
            summary = company_summary(company)
            query.present? ? summary.merge("name_match" => name_match(query, company.name)) : summary
          end
        )
      end
    end
  end
end
