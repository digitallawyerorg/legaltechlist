class CompanyVerifierAgent
  SPAM_KEYWORDS = %w[casino betting porn escort xxx adult].freeze
  MARKETING_TERMS = [
    "leading",
    "best",
    "revolutionary",
    "cutting-edge",
    "world-class",
    "game-changing"
  ].freeze

  def self.call(company, evidence_payload:)
    new(company, evidence_payload: evidence_payload).call
  end

  def initialize(company, evidence_payload:)
    @company = company
    @evidence_payload = evidence_payload
  end

  def call
    {
      "agent" => self.class.name,
      "company_id" => company.id,
      "generated_at" => Time.current.utc.iso8601,
      "verdict" => verdict,
      "quality_score" => quality_score,
      "risks" => risks,
      "duplicate_signals" => duplicate_signals,
      "taxonomy_signals" => taxonomy_signals,
      "proposed_corrections" => proposed_corrections,
      "rationale" => rationale
    }
  end

  private

  attr_reader :company, :evidence_payload

  def verdict
    return "reject_or_hide_pending_review" if spam_risk?
    return "needs_human_review" if risks.any?

    "likely_valid_needs_human_confirmation"
  end

  def quality_score
    score = 100
    score -= 25 if company.main_url.blank?
    score -= 20 if weak_description?
    score -= 20 if duplicate_domain_candidate?
    score -= 15 if duplicate_name_candidate?
    score -= 15 if unknown_taxonomy?
    score -= 30 if spam_risk?
    [[score, 0].max, 100].min
  end

  def risks
    flagged = []
    flagged << "Missing primary company URL." if company.main_url.blank?
    flagged << "Weak or short description." if weak_description?
    flagged << "Description contains marketing language." if marketing_language?
    flagged << "Duplicate-domain candidate." if duplicate_domain_candidate?
    flagged << "Duplicate-name candidate." if duplicate_name_candidate?
    flagged << "Unknown taxonomy." if unknown_taxonomy?
    flagged << "No tags assigned." if company.tags.empty?
    flagged << "Missing M2M target client assignments." if company.target_clients.empty? && company.target_client_id.blank?
    flagged << "Potential spam keyword match." if spam_risk?
    flagged << "No supporting external evidence URLs beyond the current record." if Array(evidence_payload["evidence"]).empty?
    flagged
  end

  def duplicate_signals
    {
      "normalized_name" => company.normalized_name,
      "canonical_domain" => company.canonical_domain.presence || company.canonical_main_domain,
      "duplicate_name_candidate" => duplicate_name_candidate?,
      "duplicate_domain_candidate" => duplicate_domain_candidate?
    }
  end

  def taxonomy_signals
    {
      "category" => company.category&.name,
      "secondary_category" => company.secondary_category&.name,
      "revenue_models" => company.revenue_model_names,
      "target_client" => company.target_client&.name,
      "target_clients" => company.audience_names,
      "tags" => company.tags.limit(10).pluck(:name),
      "ai_capability" => AiCapabilityDerivationService.call(company: company),
      "unknown_category" => company.category&.name == "Unknown",
      "unknown_revenue_model" => company.revenue_models.empty?,
      "unknown_target_client" => company.audience_names.blank? || company.audience_names.include?("Unknown"),
      "missing_tags" => company.tags.empty?
    }
  end

  def proposed_corrections
    corrections = {
      "quality_status" => "needs_review",
      "verification_verdict" => verdict,
      "quality_score" => quality_score
    }

    calculated_domain = company.canonical_main_domain
    corrections["canonical_domain"] = calculated_domain if calculated_domain.present? && calculated_domain != company.canonical_domain

    calculated_fingerprint = company.calculated_fingerprint
    corrections["fingerprint"] = calculated_fingerprint if calculated_fingerprint.present? && calculated_fingerprint != company.fingerprint

    if weak_description? || marketing_language?
      corrections["description_review"] = "Draft a new neutral, source-backed TechIndex description before marking reviewed."
    end

    corrections
  end

  def rationale
    if risks.any?
      "This record needs human review because one or more quality, evidence, duplicate, taxonomy, or spam checks were flagged."
    else
      "No deterministic risk flags were found, but Stanford-grade publication still requires human confirmation."
    end
  end

  def weak_description?
    company.description.to_s.squish.length < 80
  end

  def marketing_language?
    description = company.description.to_s.downcase
    MARKETING_TERMS.any? { |term| description.include?(term) }
  end

  def duplicate_name_candidate?
    Company.duplicate_name_candidate_ids.include?(company.id)
  end

  def duplicate_domain_candidate?
    Company.duplicate_domain_candidate_ids.include?(company.id)
  end

  def unknown_taxonomy?
    company.category&.name == "Unknown" ||
      company.revenue_models.empty? ||
      (company.target_client_id.blank? && company.target_clients.empty?) ||
      company.audience_names.include?("Unknown")
  end

  def spam_risk?
    text = [company.name, company.description, company.main_url].compact.join(" ").downcase
    SPAM_KEYWORDS.any? { |keyword| text.include?(keyword) }
  end
end
