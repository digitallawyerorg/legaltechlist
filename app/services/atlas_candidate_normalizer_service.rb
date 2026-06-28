class AtlasCandidateNormalizerService
  SOURCE_DESCRIPTION_POLICY = "Do not copy into TechIndex. Use only as evidence for a new neutral description after human review.".freeze

  def self.call(row)
    new(row).call
  end

  def initialize(row)
    @row = row
  end

  def call
    name = candidate_name
    website = clean_url(row["Website"])
    canonical_domain = Company.canonical_domain_for(website)
    normalized_name = Company.normalized_name_value(name)
    name_matches = name_match_payloads(normalized_name)
    domain_matches = domain_match_payloads(canonical_domain)

    {
      "status" => name_matches.any? || domain_matches.any? ? "existing_or_possible_duplicate" : "absent_candidate",
      "name" => name,
      "normalized_name" => normalized_name,
      "website" => website,
      "canonical_domain" => canonical_domain,
      "crunchbase_url" => clean_url(row["Organization Name URL"]),
      "linkedin_url" => clean_url(row["LinkedIn"]),
      "location" => row["Headquarters Location"].to_s.strip.presence,
      "founded_date" => row["Founded Date"].to_s.strip.presence,
      "operating_status" => row["Operating Status"].to_s.strip.presence,
      "company_type" => row["Company Type"].to_s.strip.presence,
      "industries" => split_list(row["Industries"]),
      "funding_amount_usd" => row["Total Funding Amount (in USD)"].to_s.strip.presence,
      "number_of_funding_rounds" => row["Number of Funding Rounds"].to_s.strip.presence,
      "founders" => row["Founders"].to_s.strip.presence,
      "source_description" => row["Description"].to_s.strip.presence,
      "full_source_description" => row["Full Description"].to_s.strip.presence,
      "source_description_policy" => SOURCE_DESCRIPTION_POLICY,
      "name_matches" => name_matches,
      "domain_matches" => domain_matches,
      "recommended_action" => recommended_action(name_matches, domain_matches)
    }
  end

  private

  attr_reader :row

  def candidate_name
    row["Organization Name"].to_s.strip
  end

  def name_match_payloads(normalized_name)
    return [] if normalized_name.blank?

    Company.where.not(name: [nil, ""]).select { |company| company.visible? && company.normalized_name == normalized_name }.first(10).map { |company| company_payload(company) }
  end

  def domain_match_payloads(canonical_domain)
    return [] if canonical_domain.blank?

    Company.where.not(main_url: [nil, ""]).select { |company| company.visible? && (company.canonical_domain.presence || company.canonical_main_domain) == canonical_domain }.first(10).map { |company| company_payload(company) }
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

  def recommended_action(name_matches, domain_matches)
    return "Review existing domain match before importing." if domain_matches.any?
    return "Review existing name match before importing." if name_matches.any?

    "Candidate appears absent; queue for human candidate-import review before creating any company record."
  end

  def split_list(value)
    value.to_s.split(",").map(&:strip).compact_blank
  end

  def clean_url(url)
    value = url.to_s.strip
    return nil if value.blank?

    value.match?(%r{\Ahttps?://}i) ? value : "https://#{value}"
  end
end
