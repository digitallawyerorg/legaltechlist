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
      "tool_results" => tool_results,
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
    Array(stored_source_lookup["sources"]).map do |source|
      evidence_item(source["label"].to_s.humanize, source["url"], "Stored #{source['label'].to_s.humanize.downcase} on the company record.")
    end.compact
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

  def tool_results
    {
      "domain_normalization" => domain_normalization,
      "duplicate_lookup" => duplicate_lookup,
      "stored_source_lookup" => stored_source_lookup,
      "taxonomy_lookup" => taxonomy_lookup,
      "web_evidence" => web_evidence
    }
  end

  def domain_normalization
    @domain_normalization ||= DomainNormalizationTool.new.call({ name: company.name, url: company.main_url })
  end

  def duplicate_lookup
    @duplicate_lookup ||= DuplicateLookupTool.new.call({ company_id: company.id, name: company.name, url: company.main_url })
  end

  def stored_source_lookup
    @stored_source_lookup ||= StoredSourceLookupTool.new.call({ company_id: company.id })
  end

  def taxonomy_lookup
    @taxonomy_lookup ||= TaxonomyLookupTool.new.call({ company_id: company.id })
  end

  def web_evidence
    @web_evidence ||= WebEvidenceTool.new.call({ company_id: company.id })
  end
end
