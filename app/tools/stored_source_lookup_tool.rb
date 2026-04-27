class StoredSourceLookupTool < RubyLLM::Tool
  description "Return stored source and profile URLs for a company record. Read-only."

  param :company_id, type: :integer, desc: "Company id to inspect."

  def execute(company_id:)
    company = Company.find_by(id: company_id)
    return { "error" => "Company not found.", "company_id" => company_id, "read_only" => true } unless company

    {
      "company_id" => company.id,
      "company_name" => company.name,
      "sources" => sources_for(company),
      "read_only" => true
    }
  end

  private

  def sources_for(company)
    {
      "main_url" => company.main_url,
      "source_url" => company.source_url,
      "crunchbase_url" => company.crunchbase_url,
      "linkedin_url" => company.linkedin_url,
      "twitter_url" => company.twitter_url,
      "facebook_url" => company.facebook_url,
      "angellist_url" => company.angellist_url
    }.filter_map do |label, url|
      next if url.blank?

      {
        "label" => label,
        "url" => url,
        "domain" => Company.canonical_domain_for(url)
      }
    end
  end
end
