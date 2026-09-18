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
    found = matches(name, canonical_domain)
    name_matches = name_match_payloads(found)
    domain_matches = domain_match_payloads(found)

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

  # The same matcher the approval gate and the review queue use. This used to compare
  # exact normalized names and exact canonical domains of its own, so a clearance check
  # here could come back absent on a company the gate would later block — which is how a
  # curator cleared a submission for a brand the index already published on another TLD.
  # Hidden drafts count, and each match carries its own `visible` flag: excluding them is
  # what let a second approval mint a duplicate of a company the first approval had
  # created but not yet published.
  def matches(name, canonical_domain)
    @matches ||= CompanyIdentityMatcher.matches_for(
      name: name,
      domains: [canonical_domain],
      profiles: CompanyIdentityMatcher.profile_keys(
        "linkedin_url" => clean_url(row["LinkedIn"]),
        "crunchbase_url" => clean_url(row["Organization Name URL"])
      )
    )
  end

  def name_match_payloads(matches)
    CompanyIdentityMatcher.name_matches(matches)
  end

  def domain_match_payloads(matches)
    CompanyIdentityMatcher.domain_matches(matches)
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
