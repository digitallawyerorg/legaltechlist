class ManualCompanyReviewService
  RUN_TYPE = "manual_company_review".freeze
  AGENT_NAME = "ManualCompanyReviewService".freeze

  def self.call(company:, reviewer: nil, notes: nil)
    new(company: company, reviewer: reviewer, notes: notes).call
  end

  def initialize(company:, reviewer: nil, notes: nil)
    @company = company
    @reviewer = reviewer
    @notes = notes
  end

  def call
    run = PipelineRun.create!(
      name: "Manual company review: #{company.name}",
      run_type: RUN_TYPE,
      status: "pending",
      agent_name: AGENT_NAME,
      details: details_payload
    )

    run.mark_running!
    run.mark_succeeded!(records_processed: 1, details: details_payload.merge("completed_at" => Time.current.utc.iso8601))
    run
  rescue StandardError => e
    run&.mark_failed!(e.message, details: details_payload.merge("failed_at" => Time.current.utc.iso8601))
    raise
  end

  private

  attr_reader :company, :reviewer, :notes

  def details_payload
    @details_payload ||= {
      "company_id" => company.id,
      "reviewer" => reviewer,
      "notes" => notes,
      "mode" => "manual_no_public_writes",
      "current_record" => current_record,
      "evidence" => evidence,
      "duplicate_signals" => duplicate_signals,
      "proposed_corrections" => proposed_corrections,
      "risks" => risks,
      "created_at" => Time.current.utc.iso8601
    }
  end

  def current_record
    {
      "name" => company.name,
      "description" => company.description,
      "main_url" => company.main_url,
      "canonical_domain" => company.canonical_domain,
      "calculated_canonical_domain" => company.canonical_main_domain,
      "fingerprint" => company.fingerprint,
      "calculated_fingerprint" => company.calculated_fingerprint,
      "category" => company.category&.name,
      "revenue_models" => company.revenue_model_names,
      "target_client" => company.target_client&.name,
      "visible" => company.visible,
      "quality_status" => company.quality_status,
      "verification_verdict" => company.verification_verdict,
      "quality_score" => company.quality_score
    }
  end

  def evidence
    items = []
    items << evidence_item("Company website", company.main_url, "Primary website listed on the current TechIndex record.") if company.main_url.present?
    items << evidence_item("Source URL", company.source_url, "Source URL already stored on the company record.") if company.source_url.present?
    items << evidence_item("Crunchbase URL", company.crunchbase_url, "Crunchbase URL already stored on the company record.") if company.crunchbase_url.present?
    items
  end

  def evidence_item(title, url, summary)
    {
      "title" => title,
      "url" => url,
      "summary" => summary
    }
  end

  def duplicate_signals
    {
      "normalized_name" => company.normalized_name,
      "canonical_domain" => company.canonical_domain.presence || company.canonical_main_domain,
      "duplicate_name_candidate" => Company.duplicate_name_candidate_ids.include?(company.id),
      "duplicate_domain_candidate" => Company.duplicate_domain_candidate_ids.include?(company.id)
    }
  end

  def proposed_corrections
    corrections = {
      "quality_status" => "needs_review",
      "verification_verdict" => "manual_review_required"
    }

    calculated_domain = company.canonical_main_domain
    corrections["canonical_domain"] = calculated_domain if calculated_domain.present? && calculated_domain != company.canonical_domain

    calculated_fingerprint = company.calculated_fingerprint
    corrections["fingerprint"] = calculated_fingerprint if calculated_fingerprint.present? && calculated_fingerprint != company.fingerprint

    if company.description.to_s.squish.length < 80
      corrections["description_review"] = "Description is short or thin. Draft a neutral, source-backed TechIndex description before marking reviewed."
    end

    corrections
  end

  def risks
    flagged_risks = []
    flagged_risks << "Missing company URL." if company.main_url.blank?
    flagged_risks << "Weak or short description." if company.description.to_s.squish.length < 80
    flagged_risks << "Duplicate-name candidate." if Company.duplicate_name_candidate_ids.include?(company.id)
    flagged_risks << "Duplicate-domain candidate." if Company.duplicate_domain_candidate_ids.include?(company.id)
    flagged_risks << "Unknown taxonomy." if company.category_id.blank? || company.revenue_models.empty? || company.target_client_id.blank?
    flagged_risks.presence || ["No obvious automated risk flags; still requires human verification before marking reviewed."]
  end
end
