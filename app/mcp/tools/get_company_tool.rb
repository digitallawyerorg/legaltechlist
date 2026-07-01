module Mcp
  module Tools
    class GetCompanyTool < BaseTool
      tool_name "get_company"
      title "Get company"
      description "Fetch a single company profile (by slug or id) with taxonomy, funding, quality signals, and duplicate matches."
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, title: "Get company")
      input_schema(
        properties: {
          slug: { type: "string", description: "Company slug or numeric id." }
        },
        required: ["slug"]
      )

      def self.call(server_context:, slug:)
        company = find_company(slug)
        return not_found("Company '#{slug}' not found") unless company

        name_dupes = Company.duplicates_by_normalized_name_for(company).limit(10).map { |c| { "id" => c.id, "name" => c.name, "slug" => c.slug } }
        domain_dupes = Company.duplicates_by_domain_for(company).first(10).map { |c| { "id" => c.id, "name" => c.name, "slug" => c.slug } }

        json_response(
          company_summary(company).merge(
            "description" => company.description,
            "revenue_models" => company.revenue_model_names,
            "target_clients" => company.audience_names,
            "tags" => company.tags.map(&:name),
            "total_funding_amount_usd" => company.total_funding_amount_usd,
            "funding_status" => company.funding_status,
            "crunchbase_url" => company.crunchbase_url,
            "linkedin_url" => company.linkedin_url,
            "legalio_url" => company.legalio_url,
            "canonical_domain" => company.canonical_domain.presence || company.canonical_main_domain,
            "duplicate_name_matches" => name_dupes,
            "duplicate_domain_matches" => domain_dupes
          )
        )
      end
    end
  end
end
