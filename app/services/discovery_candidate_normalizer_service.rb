class DiscoveryCandidateNormalizerService
  def self.call(discovery_hash)
    new(discovery_hash).call
  end

  def initialize(discovery_hash)
    @discovery_hash = discovery_hash
  end

  def call
    normalized = AtlasCandidateNormalizerService.call(atlas_row)
    normalized = normalized.merge(discovery_metadata)
    apply_nonprofit_advocacy_filter(normalized)
  end

  private

  attr_reader :discovery_hash

  def atlas_row
    # NOTE: the discovery description is intentionally NOT mapped to the Atlas
    # "Description" (which becomes source_description) — for discovery candidates the
    # LLM sentence IS the neutral draft, so it is promoted to the proposal description
    # (see CompanyCandidateRowProcessorService) rather than kept as third-party source
    # text that the copied-source guard would flag.
    {
      "Organization Name" => discovery_hash["name"],
      "Website" => discovery_hash["website"],
      "Headquarters Location" => discovery_hash["location"],
      "Founded Date" => discovery_hash["founded_date"],
      "Operating Status" => discovery_hash["operating_status"].presence || "Active"
    }
  end

  def apply_nonprofit_advocacy_filter(normalized)
    return normalized unless normalized["status"] == "absent_candidate"
    return normalized unless DiscoveryNonprofitAdvocacyFilter.rejected?(discovery_hash.merge(normalized.slice("name", "website", "description", "why_discovered", "location")))

    normalized.merge(
      "status" => "rejected_nonprofit_advocacy",
      "rejection_reason" => DiscoveryNonprofitAdvocacyFilter.rejection_reason(discovery_hash.merge(normalized.slice("name", "website", "description", "why_discovered", "location")))
    )
  end

  def discovery_metadata
    {
      "discovery_source" => "llm_discovery",
      "discovery_type" => discovery_hash["discovery_type"],
      "why_discovered" => discovery_hash["why_discovered"].to_s.strip.presence,
      "website_verified" => discovery_hash["website_verified"],
      "discovery_query" => discovery_hash["discovery_query"],
      "funding_round_year" => discovery_hash["funding_round_year"],
      "funding_round_type" => discovery_hash["funding_round_type"],
      "funding_amount_hint" => discovery_hash["funding_amount_hint"],
      "category_name" => discovery_hash["category_name"],
      "business_model_names" => discovery_hash["business_model_names"].presence,
      "target_client_names" => discovery_hash["target_client_names"].presence,
      "founded_year_source" => discovery_hash["founded_year_source"],
      "discovery_description" => discovery_hash["description"].to_s.squish.presence
    }.compact
  end
end
