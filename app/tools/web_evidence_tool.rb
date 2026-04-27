class WebEvidenceTool < RubyLLM::Tool
  description "Create read-only web evidence candidates from a company record and optionally check a URL with a HEAD request."

  param :company_id, type: :integer, desc: "Company id to inspect.", required: false
  param :url, desc: "Specific URL to inspect.", required: false

  def execute(company_id: nil, url: nil)
    company = Company.find_by(id: company_id) if company_id.present?
    urls = ([url] + stored_urls(company)).compact_blank.uniq

    {
      "company_id" => company_id,
      "urls" => urls.map { |candidate_url| evidence_payload(candidate_url) },
      "network_checked" => network_checks_enabled?,
      "read_only" => true
    }
  end

  private

  def stored_urls(company)
    return [] unless company

    [
      company.main_url,
      company.source_url,
      company.crunchbase_url,
      company.linkedin_url
    ]
  end

  def evidence_payload(url)
    {
      "url" => url,
      "domain" => Company.canonical_domain_for(url),
      "status" => network_status(url)
    }.compact
  end

  def network_status(url)
    return "not_checked" unless network_checks_enabled?

    response = Faraday.head(url) do |request|
      request.options.timeout = ENV.fetch("AGENT_WEB_EVIDENCE_TIMEOUT", "5").to_i
      request.options.open_timeout = ENV.fetch("AGENT_WEB_EVIDENCE_OPEN_TIMEOUT", "3").to_i
    end
    response.status
  rescue StandardError => e
    "error: #{e.class.name}"
  end

  def network_checks_enabled?
    ENV.fetch("AGENT_WEB_EVIDENCE_NETWORK_CHECKS", "false") == "true"
  end
end
