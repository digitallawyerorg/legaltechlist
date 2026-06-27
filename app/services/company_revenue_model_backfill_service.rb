require "timeout"

class CompanyRevenueModelBackfillService
  HIGH_CONFIDENCE = 0.85
  REVIEW_CONFIDENCE = 0.65

  GRANT_SIGNAL_TAGS = %w[
    nonprofit
    non-profit
    legal aid
    access to justice
    pro bono
    grant
    foundation
    subsidized
  ].freeze

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(company:, dry_run: true, min_confidence: HIGH_CONFIDENCE, overwrite_unknown_only: true)
    @company = company
    @dry_run = dry_run
    @min_confidence = min_confidence
    @overwrite_unknown_only = overwrite_unknown_only
  end

  def call
    current_names = company.revenue_model_names
    return skip_result("human_reviewed") if company.human_reviewed_at.present?
    return skip_result("already_classified") if overwrite_unknown_only && current_names.any? && !current_names.intersect?(%w[Unknown])

    suggestion = CompanyProposalTaxonomySuggestionService.call(
      source_payload: source_payload,
      final_changes: { "name" => company.name, "description" => company.description }
    )
    names = Array(suggestion.dig("revenue_models", "names")).uniq
    confidence = suggestion.dig("revenue_models", "confidence").to_f
    mode = suggestion["mode"]

    names = apply_grant_heuristics(names)
    confidence = [confidence, grant_heuristic_confidence(names)].max
    names = ["Other"] if names.empty?

    result = {
      "company_id" => company.id,
      "company_name" => company.name,
      "current_revenue_models" => current_names,
      "suggested_revenue_models" => names,
      "confidence" => confidence,
      "mode" => mode,
      "applied" => false,
      "dry_run" => dry_run
    }

    if confidence >= min_confidence
      unless dry_run
        company.business_model_ids = BusinessModel.where(name: names).pluck(:id)
        company.save!(validate: false)
        result["applied"] = true
      end
      result["action"] = dry_run ? "would_apply" : "applied"
    elsif confidence >= REVIEW_CONFIDENCE
      result["action"] = "needs_review"
    else
      result["action"] = "skipped_low_confidence"
    end

    result
  end

  private

  attr_reader :company, :dry_run, :min_confidence, :overwrite_unknown_only

  def source_payload
    {
      "name" => company.name,
      "website" => company.main_url,
      "source_description" => company.description,
      "industries" => [company.category&.name, company.target_client&.name].compact
    }
  end

  def apply_grant_heuristics(names)
    return names if names.include?("Grants & Subsidies")

    names += ["Grants & Subsidies"] if strong_grant_signals?
    names.uniq
  end

  def grant_heuristic_confidence(names)
    return 0.0 unless names.include?("Grants & Subsidies")

    strong_grant_signals? ? 0.9 : 0.0
  end

  def strong_grant_signals?
    tag_hits = company.tags.map { |tag| tag.name.to_s.downcase }
    grant_tag_matches = tag_hits.count { |tag| GRANT_SIGNAL_TAGS.any? { |signal| tag.include?(signal) } }
    text = [company.name, company.description, company.target_client&.name].compact.join(" ").downcase

    grant_tag_matches >= 2 ||
      (grant_tag_matches >= 1 && text.match?(/\b(grant|donation|subsidy|legal aid|nonprofit|501\(c\)|foundation)\b/)) ||
      text.match?(/\b(grant-funded|publicly funded|government funded|legal services corporation|lsc\b)\b/)
  end

  def skip_result(reason)
    {
      "company_id" => company.id,
      "company_name" => company.name,
      "current_revenue_models" => company.revenue_model_names,
      "action" => "skipped_#{reason}",
      "applied" => false,
      "dry_run" => dry_run
    }
  end
end
