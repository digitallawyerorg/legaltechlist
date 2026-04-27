class DuplicateLookupTool < RubyLLM::Tool
  description "Look up possible duplicate companies by normalized name and canonical domain. Read-only."

  param :company_id, type: :integer, desc: "Existing company id to exclude from candidate lists.", required: false
  param :name, desc: "Company name to compare.", required: false
  param :url, desc: "Company URL to compare.", required: false

  def execute(company_id: nil, name: nil, url: nil)
    normalized_name = Company.normalized_name_value(name)
    canonical_domain = Company.canonical_domain_for(url)

    {
      "lookup" => {
        "company_id" => company_id,
        "normalized_name" => normalized_name.presence,
        "canonical_domain" => canonical_domain
      },
      "name_candidates" => name_candidates(normalized_name, company_id),
      "domain_candidates" => domain_candidates(canonical_domain, company_id),
      "read_only" => true
    }
  end

  private

  def name_candidates(normalized_name, company_id)
    return [] if normalized_name.blank?

    Company.where.not(name: [nil, ""]).where.not(id: company_id).select { |company| company.normalized_name == normalized_name }.first(10).map { |company| company_payload(company) }
  end

  def domain_candidates(canonical_domain, company_id)
    return [] if canonical_domain.blank?

    Company.where.not(main_url: [nil, ""]).where.not(id: company_id).select { |company| (company.canonical_domain.presence || company.canonical_main_domain) == canonical_domain }.first(10).map { |company| company_payload(company) }
  end

  def company_payload(company)
    {
      "id" => company.id,
      "name" => company.name,
      "main_url" => company.main_url,
      "canonical_domain" => company.canonical_domain.presence || company.canonical_main_domain,
      "visible" => company.visible,
      "quality_status" => company.quality_status
    }
  end
end
