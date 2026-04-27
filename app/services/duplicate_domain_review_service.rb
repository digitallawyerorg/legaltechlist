class DuplicateDomainReviewService
  RUN_TYPE = "duplicate_domain_review".freeze
  AGENT_NAME = "DuplicateReviewAgent".freeze

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
      name: "Duplicate-domain review: #{company.name}",
      run_type: RUN_TYPE,
      status: "pending",
      agent_name: AGENT_NAME
    )

    run.mark_running!
    run.mark_succeeded!(records_processed: candidate_companies.size + 1, details: details_payload)
    run
  rescue StandardError => e
    run&.mark_failed!(e.message, details: failure_payload(e))
    raise
  end

  private

  attr_reader :company, :reviewer, :notes

  def details_payload
    duplicate_review = DuplicateReviewAgent.call(company, candidates: candidate_companies)

    {
      "company_id" => company.id,
      "candidate_company_ids" => candidate_companies.map(&:id),
      "reviewer" => reviewer,
      "notes" => notes,
      "mode" => "duplicate_review_no_public_writes",
      "primary_company" => company_payload(company),
      "candidate_companies" => candidate_companies.map { |candidate| company_payload(candidate) },
      "duplicate_review" => duplicate_review,
      "proposed_corrections" => {
        "duplicate_review_recommendation" => duplicate_review["overall_recommendation"],
        "duplicate_relationships" => duplicate_review["pair_reviews"]
      },
      "risks" => risks(duplicate_review),
      "created_at" => Time.current.utc.iso8601,
      "completed_at" => Time.current.utc.iso8601
    }
  end

  def failure_payload(error)
    {
      "company_id" => company.id,
      "reviewer" => reviewer,
      "notes" => notes,
      "mode" => "duplicate_review_no_public_writes",
      "error_class" => error.class.name,
      "failed_at" => Time.current.utc.iso8601
    }
  end

  def candidate_companies
    @candidate_companies ||= begin
      domain = canonical_domain(company)
      return [] if domain.blank?

      Company.includes(:category, :business_model, :target_client).where.not(id: company.id).where.not(main_url: [nil, ""]).select { |candidate| canonical_domain(candidate) == domain }.first(10)
    end
  end

  def company_payload(record)
    {
      "id" => record.id,
      "name" => record.name,
      "description" => record.description,
      "main_url" => record.main_url,
      "canonical_domain" => canonical_domain(record),
      "category" => record.category&.name,
      "business_model" => record.business_model&.name,
      "target_client" => record.target_client&.name,
      "visible" => record.visible,
      "quality_status" => record.quality_status,
      "updated_at" => record.updated_at&.utc&.iso8601
    }
  end

  def canonical_domain(record)
    record.canonical_domain.presence || record.canonical_main_domain
  end

  def risks(duplicate_review)
    flagged = ["Duplicate-domain candidate."]
    flagged << "No candidate company records were found for this domain." if candidate_companies.blank?
    flagged << "Human review required before merge, deletion, hiding, or overwrite."
    flagged << "Agent recommendation: #{duplicate_review['overall_recommendation']}"
    flagged
  end
end
