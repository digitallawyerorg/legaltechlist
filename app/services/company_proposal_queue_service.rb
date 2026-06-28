class CompanyProposalQueueService
  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(pipeline_run:, candidate_indexes:, admin_user:)
    @pipeline_run = pipeline_run
    @candidate_indexes = Array(candidate_indexes).map(&:to_i)
    @admin_user = admin_user
  end

  def call
    validate_run!

    selected_candidates.filter_map { |candidate| create_proposal(candidate) }
  end

  private

  attr_reader :pipeline_run, :candidate_indexes, :admin_user

  def validate_run!
    raise ArgumentError, "Pipeline run is not an Atlas candidate import review" unless pipeline_run.run_type == AtlasCandidateImportReviewService::RUN_TYPE
    raise ArgumentError, "Select at least one candidate" if candidate_indexes.empty?
  end

  def selected_candidates
    candidates = Array(pipeline_run.details&.fetch("candidates", []))
    candidate_indexes.filter_map { |index| candidates[index] }
  end

  def create_proposal(candidate)
    return unless candidate["status"] == "absent_candidate"

    source_identifier = candidate["canonical_domain"].presence || Company.normalized_name_value(candidate["name"])
    CompanyProposal.find_or_create_by!(source: "legaltechatlas_csv", source_identifier: source_identifier) do |proposal|
      proposal.status = "pending"
      proposal.proposal_type = "atlas_candidate"
      proposal.admin_user = admin_user
      proposal.source_payload = candidate
      proposal.proposed_changes = proposed_changes(candidate)
      proposal.final_changes = proposed_changes(candidate)
      proposal.duplicate_signals = duplicate_signals(candidate)
      proposal.reviewer_notes = "Queued from PipelineRun##{pipeline_run.id}. Source descriptions are evidence only and must not be copied."
    end
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
      "source" => "LegalTechAtlas CSV",
      "source_url" => candidate["crunchbase_url"].presence || candidate["website"],
      "category_id" => nil,
      "business_model_id" => nil,
      "target_client_id" => nil
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
