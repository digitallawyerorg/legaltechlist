class CompanyEvidenceAgent
  def self.call(company)
    new(company).call
  end

  def initialize(company)
    @company = company
  end

  def call
    {
      "agent" => self.class.name,
      "company_id" => company.id,
      "generated_at" => Time.current.utc.iso8601,
      "current_record" => current_record,
      "evidence" => evidence,
      "evidence_gaps" => evidence_gaps
    }
  end

  private

  attr_reader :company

  def current_record
    {
      "name" => company.name,
      "description" => company.description,
      "main_url" => company.main_url,
      "canonical_domain" => company.canonical_domain.presence || company.canonical_main_domain,
      "category" => company.category&.name,
      "business_model" => company.business_model&.name,
      "target_client" => company.target_client&.name,
      "status" => company.status,
      "visible" => company.visible
    }
  end

  def evidence
    [
      evidence_item("Company website", company.main_url, "Primary website listed in TechIndex."),
      evidence_item("Crunchbase", company.crunchbase_url, "Crunchbase profile listed in TechIndex."),
      evidence_item("LinkedIn", company.linkedin_url, "LinkedIn profile listed in TechIndex."),
      evidence_item("Source URL", company.source_url, "Source/provenance URL stored on the company record."),
      evidence_item("Twitter/X", company.twitter_url, "Social profile listed in TechIndex."),
      evidence_item("Facebook", company.facebook_url, "Social profile listed in TechIndex.")
    ].compact
  end

  def evidence_item(title, url, summary)
    return if url.blank?

    {
      "title" => title,
      "url" => url,
      "domain" => Company.canonical_domain_for(url),
      "summary" => summary
    }
  end

  def evidence_gaps
    gaps = []
    gaps << "Missing primary company URL." if company.main_url.blank?
    gaps << "No Crunchbase URL stored." if company.crunchbase_url.blank?
    gaps << "No LinkedIn URL stored." if company.linkedin_url.blank?
    gaps << "No source/provenance URL stored." if company.source_url.blank?
    gaps
  end
end
