class DiscoveryCandidateNormalizerService
  def self.call(discovery_hash)
    new(discovery_hash).call
  end

  def initialize(discovery_hash)
    @discovery_hash = discovery_hash
  end

  def call
    normalized = AtlasCandidateNormalizerService.call(atlas_row)
    normalized.merge(discovery_metadata)
  end

  private

  attr_reader :discovery_hash

  def atlas_row
    {
      "Organization Name" => discovery_hash["name"],
      "Website" => discovery_hash["website"],
      "Headquarters Location" => discovery_hash["location"],
      "Founded Date" => discovery_hash["founded_date"],
      "Description" => discovery_hash["description"],
      "Operating Status" => discovery_hash["operating_status"].presence || "Active"
    }
  end

  def discovery_metadata
    {
      "discovery_source" => "llm_discovery",
      "discovery_type" => discovery_hash["discovery_type"],
      "why_discovered" => discovery_hash["why_discovered"].to_s.strip.presence,
      "website_verified" => discovery_hash["website_verified"],
      "discovery_query" => discovery_hash["discovery_query"]
    }.compact
  end
end
