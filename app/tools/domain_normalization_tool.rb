class DomainNormalizationTool < RubyLLM::Tool
  description "Normalize company names and URLs into canonical domains and stable fingerprints. Read-only."

  param :name, desc: "Company name to normalize.", required: false
  param :url, desc: "Company or evidence URL to normalize.", required: false

  def execute(name: nil, url: nil)
    normalized_name = Company.normalized_name_value(name)
    canonical_domain = Company.canonical_domain_for(url)

    {
      "input_name" => name,
      "input_url" => url,
      "normalized_name" => normalized_name.presence,
      "canonical_domain" => canonical_domain,
      "fingerprint" => Company.fingerprint_for(name, url),
      "read_only" => true
    }
  end
end
