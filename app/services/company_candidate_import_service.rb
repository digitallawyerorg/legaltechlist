class CompanyCandidateImportService
  SOURCE = "legaltechatlas_csv".freeze
  DEFAULT_LIMIT = AtlasCandidateImportReviewService::DEFAULT_MAX_LIMIT

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(file:, admin_user:, notes: nil, limit: DEFAULT_LIMIT)
    @file = file
    @admin_user = admin_user
    @notes = notes
    @limit = limit.to_i
  end

  def call
    @run = AtlasCandidateImportReviewService.call(file: file, reviewer: admin_user.email, notes: notes, limit: limit, max_limit: DEFAULT_LIMIT)
    results = candidates.each_with_index.map { |candidate, index| process_candidate(candidate, index) }
    @run.update!(details: @run.details.merge("automation" => automation_summary(results), "automation_results" => results))
    @run
  end

  private

  attr_reader :file, :admin_user, :notes, :limit

  def candidates
    @candidates ||= Array(run_details["candidates"])
  end

  def run_details
    @run_details ||= @run&.details || {}
  end

  def process_candidate(candidate, index)
    proposal = upsert_proposal(candidate, index)
    return result_payload(candidate, index, proposal, "needs_duplicate_review", "Duplicate or existing-record signal found.") if proposal.duplicate_blocking?

    CompanyProposalEnrichmentService.call(proposal: proposal, admin_user: admin_user)
    proposal.reload

    quality = CompanyProposalQualityService.call(proposal)
    return result_payload(candidate, index, proposal, "needs_review", Array(quality["blockers"]).first) unless auto_draft_ready?(proposal, quality)
    return result_payload(candidate, index, proposal, "already_drafted", "Proposal already has a company draft.") if proposal.company_id.present?

    company = create_hidden_draft!(proposal)
    result_payload(candidate, index, proposal.reload, "auto_drafted", "Invisible company draft created.", company)
  end

  def upsert_proposal(candidate, index)
    source_identifier = source_identifier(candidate)
    proposal = CompanyProposal.find_or_initialize_by(source: SOURCE, source_identifier: source_identifier)
    proposal.assign_attributes(
      status: proposal.company_id.present? ? proposal.status : "pending",
      proposal_type: "atlas_candidate",
      admin_user: admin_user,
      source_payload: candidate.merge("source_row_index" => index, "pipeline_run_id" => @run.id),
      proposed_changes: proposed_changes(candidate),
      final_changes: proposal.final_changes.presence || proposed_changes(candidate),
      duplicate_signals: duplicate_signals(candidate),
      reviewer_notes: reviewer_notes(candidate)
    )
    proposal.save!
    proposal
  end

  def create_hidden_draft!(proposal)
    changes = proposal.final_changes.slice(*CompanyProposal::EDITABLE_COMPANY_FIELDS)
    company = Company.new(changes.merge(
      "category_id" => changes["category_id"].presence,
      "sub_category_id" => changes["sub_category_id"].presence,
      "business_model_id" => changes["business_model_id"].presence,
      "target_client_id" => changes["target_client_id"].presence
    ))
    company.visible = false
    company.quality_status = "needs_review"
    company.verification_verdict = "automated_import_draft"
    company.enriched_at = Time.current
    company.quality_reviewed_at = Time.current
    company.canonical_domain = company.canonical_main_domain
    company.fingerprint = company.calculated_fingerprint
    company.skip_geocoding = true
    company.save!

    proposal.update!(
      status: "approved_to_draft",
      company: company,
      admin_user: admin_user,
      reviewed_at: Time.current,
      approved_at: Time.current,
      reviewer_notes: [proposal.reviewer_notes, "Auto-created invisible company draft from high-confidence import data."].compact_blank.join("\n")
    )

    company
  end

  def auto_draft_ready?(proposal, quality)
    quality["publish_ready"] &&
      proposal.agent_details.dig("taxonomy_suggestion", "accepted") &&
      !proposal.duplicate_blocking?
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
      "employee_count" => candidate["employee_count"],
      "founders" => candidate["founders"],
      "source" => "LegalTechAtlas CSV",
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

  def reviewer_notes(candidate)
    if candidate["status"] == "existing_or_possible_duplicate"
      "Imported candidate requires duplicate review before any company draft is created."
    else
      "Imported candidate was processed automatically. Clean rows may become invisible drafts; exceptions remain here for review."
    end
  end

  def result_payload(candidate, index, proposal, action, reason, company = nil)
    {
      "row_index" => index,
      "name" => candidate["name"],
      "status" => candidate["status"],
      "action" => action,
      "reason" => reason,
      "proposal_id" => proposal&.id,
      "company_id" => company&.id || proposal&.company_id,
      "canonical_domain" => candidate["canonical_domain"]
    }.compact
  end

  def automation_summary(results)
    {
      "processed_rows" => results.size,
      "auto_drafted" => results.count { |result| result["action"] == "auto_drafted" },
      "already_drafted" => results.count { |result| result["action"] == "already_drafted" },
      "needs_review" => results.count { |result| result["action"] == "needs_review" },
      "needs_duplicate_review" => results.count { |result| result["action"] == "needs_duplicate_review" },
      "created_at" => Time.current.utc.iso8601
    }
  end

  def source_identifier(candidate)
    candidate["canonical_domain"].presence || Company.normalized_name_value(candidate["name"])
  end

  def location_value(candidate)
    candidate["location"].to_s.split(",").first(2).join(", ").presence
  end

  def founded_year(value)
    value.to_s[/\d{4}/]
  end

  def company_status(value)
    value.to_s.downcase == "closed" ? "inactive" : "active"
  end
end
