class CompanyAgentReviewService
  RUN_TYPE = "company_agent_review".freeze
  AGENT_NAME = "CompanyEvidenceAgent+CompanyVerifierAgent+DescriptionDraftAgent".freeze

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
      name: "Agent company review: #{company.name}",
      run_type: RUN_TYPE,
      status: "pending",
      agent_name: AGENT_NAME
    )

    run.mark_running!
    run.mark_succeeded!(records_processed: 1, details: details_payload)
    run
  rescue StandardError => e
    run&.mark_failed!(e.message, details: failure_payload(e))
    raise
  end

  private

  attr_reader :company, :reviewer, :notes

  def details_payload
    evidence_payload = CompanyEvidenceAgent.call(company)
    verification_payload = CompanyVerifierAgent.call(company, evidence_payload: evidence_payload)
    description_payload = DescriptionDraftAgent.call(company, evidence_payload: evidence_payload, verification_payload: verification_payload)
    proposed_corrections = verification_payload["proposed_corrections"].merge(
      "proposed_description" => description_payload["proposed_description"],
      "description_rationale" => description_payload["rationale"],
      "description_confidence" => description_payload["confidence"]
    )

    {
      "company_id" => company.id,
      "reviewer" => reviewer,
      "notes" => notes,
      "mode" => "agent_proposal_no_public_writes",
      "evidence" => evidence_payload["evidence"],
      "evidence_gaps" => evidence_payload["evidence_gaps"],
      "verification" => verification_payload,
      "description_draft" => description_payload,
      "duplicate_signals" => verification_payload["duplicate_signals"],
      "taxonomy_signals" => verification_payload["taxonomy_signals"],
      "proposed_corrections" => proposed_corrections,
      "risks" => verification_payload["risks"],
      "created_at" => Time.current.utc.iso8601,
      "completed_at" => Time.current.utc.iso8601
    }
  end

  def failure_payload(error)
    {
      "company_id" => company.id,
      "reviewer" => reviewer,
      "notes" => notes,
      "mode" => "agent_proposal_no_public_writes",
      "error_class" => error.class.name,
      "failed_at" => Time.current.utc.iso8601
    }
  end
end
