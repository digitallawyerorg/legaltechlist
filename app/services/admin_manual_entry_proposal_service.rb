class AdminManualEntryProposalService
  SOURCE = "admin_manual_entry"
  SOURCE_LABEL = "Admin manual entry"

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(name:, url:, admin_user:)
    @name = name.to_s.strip
    @url = url.to_s.strip
    @admin_user = admin_user
  end

  def call
    candidate = AtlasCandidateNormalizerService.call("Organization Name" => name, "Website" => url)
    proposal = upsert_proposal(candidate)
    CompanyProposalEnrichmentService.call(proposal: proposal, admin_user: admin_user)

    { proposal: proposal.reload, candidate: candidate }
  end

  private

  attr_reader :name, :url, :admin_user

  def upsert_proposal(candidate)
    source_identifier = candidate["canonical_domain"].presence || Company.normalized_name_value(candidate["name"])
    proposal = CompanyProposal.find_or_initialize_by(source: SOURCE, source_identifier: source_identifier)
    changes = proposed_changes(candidate)

    proposal.assign_attributes(
      status: proposal.company_id.present? ? proposal.status : "pending",
      proposal_type: "atlas_candidate",
      admin_user: admin_user,
      source_payload: candidate,
      proposed_changes: changes,
      final_changes: proposal.final_changes.presence || changes,
      duplicate_signals: duplicate_signals(candidate),
      reviewer_notes: "Created from admin new company form via Fill from URL. Source descriptions are evidence only and must not be copied."
    )
    proposal.save!
    proposal
  end

  def proposed_changes(candidate)
    {
      "name" => candidate["name"],
      "main_url" => candidate["website"],
      "location" => location_value(candidate),
      "founded_date" => founded_year(candidate["founded_date"]),
      "status" => company_status(candidate["operating_status"]),
      "description" => nil,
      "crunchbase_url" => candidate["crunchbase_url"],
      "linkedin_url" => candidate["linkedin_url"],
      "total_funding_amount_usd" => candidate["funding_amount_usd"],
      "funding_status" => candidate["company_type"],
      "number_of_funding_rounds" => candidate["number_of_funding_rounds"],
      "founders" => candidate["founders"],
      "source" => SOURCE_LABEL,
      "source_url" => candidate["crunchbase_url"].presence || candidate["website"]
    }.compact
  end

  def duplicate_signals(candidate)
    {
      "name_matches" => Array(candidate["name_matches"]),
      "domain_matches" => Array(candidate["domain_matches"]),
      "recommended_action" => candidate["recommended_action"]
    }
  end

  def location_value(candidate)
    LocationCountryResolver.format_for_display(candidate["location"])
  end

  def founded_year(value)
    value.to_s[/\d{4}/]
  end

  def company_status(value)
    value.to_s.downcase == "closed" ? "inactive" : "active"
  end
end
