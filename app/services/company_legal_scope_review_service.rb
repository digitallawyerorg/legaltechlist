require "timeout"

class CompanyLegalScopeReviewService
  HIGH_CONFIDENCE = 0.85
  AUTO_CONFIDENCE = 0.55

  def self.call(company:, dry_run: true, min_confidence: nil)
    new(company: company, dry_run: dry_run, min_confidence: min_confidence).call
  end

  def initialize(company:, dry_run: true, min_confidence: nil)
    @company = company
    @dry_run = dry_run
    @min_confidence = min_confidence || default_min_confidence
  end

  def call
    return skip("not_unknown") unless company.category&.name == "Unknown"

    review = llm_review
    return skip("llm_disabled") unless review

    if review["is_legal_technology"] == false && review["confidence"].to_f >= HIGH_CONFIDENCE
      unless dry_run
        company.hide_as_out_of_scope!
      end

      return {
        "company_id" => company.id,
        "company_name" => company.name,
        "action" => dry_run ? "would_hide" : "hidden",
        "confidence" => review["confidence"],
        "mode" => review["mode"],
        "reason" => review["reason"]
      }
    end

    category_name = review["category_name"].to_s
    confidence = review["category_confidence"].to_f
    if review["is_legal_technology"] && category_name.present? && category_name != "Unknown" && confidence >= min_confidence
      category = Category.find_by(name: category_name)
      return skip("missing_category", category_name, confidence, review["mode"]) unless category

      company.update!(category: category) unless dry_run
      return {
        "company_id" => company.id,
        "company_name" => company.name,
        "action" => dry_run ? "would_categorize" : "categorized",
        "to_category" => category_name,
        "confidence" => confidence,
        "mode" => review["mode"]
      }
    end

    skip("needs_human_review", category_name, confidence, review["mode"], review["reason"])
  end

  private

  attr_reader :company, :dry_run, :min_confidence

  def default_min_confidence
    return AUTO_CONFIDENCE if ENV.fetch("AUTO_HYGIENE", "false") == "true"

    ENV.fetch("MIN_CONFIDENCE", AUTO_CONFIDENCE.to_s).to_f
  end

  def llm_review
    LegalScopeReviewAgent.call(company: company)
  end

  def effective_description
    text = company.description.to_s.strip
    return nil if text.blank? || text == "No description yet"

    text
  end

  def skip(reason, category_name = nil, confidence = nil, mode = nil, review_reason = nil)
    {
      "company_id" => company.id,
      "company_name" => company.name,
      "suggested_category" => category_name,
      "confidence" => confidence,
      "mode" => mode,
      "reason" => review_reason,
      "action" => "skipped_#{reason}"
    }
  end
end
