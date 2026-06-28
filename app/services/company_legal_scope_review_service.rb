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
        company.update!(
          visible: false,
          status: "inactive",
          verification_verdict: "out_of_scope_review"
        )
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
    return unless llm_enabled?

    chat = RubyLLM.chat(model: llm_model, provider: :openai, assume_model_exists: true)
    response = Timeout.timeout(llm_timeout_seconds) { chat.ask(llm_prompt) }
    parsed = JSON.parse(response.content.to_s)
    parsed.merge("mode" => "ruby_llm")
  rescue StandardError
    nil
  end

  def llm_enabled?
    defined?(RubyLLM) &&
      ENV["OPENAI_API_KEY"].present? &&
      ENV.fetch("PROPOSAL_TAXONOMY_USE_LLM", Rails.env.production? ? "true" : "false") == "true"
  end

  def llm_model
    ENV.fetch("RUBYLLM_TAXONOMY_MODEL", ENV.fetch("RUBYLLM_HARD_MODEL", "gpt-5.5"))
  end

  def llm_timeout_seconds
    ENV.fetch("PROPOSAL_TAXONOMY_TIMEOUT_SECONDS", "45").to_i
  end

  def llm_prompt
    {
      company: {
        name: company.name,
        website: company.main_url,
        description: effective_description,
        target_clients: company.audience_names,
        tags: company.tags.map(&:name)
      },
      allowed_category_names: Category.where.not(name: "Unknown").order(:name).pluck(:name),
      instruction: "Decide whether this profile belongs in a legal-technology company index. Return JSON with is_legal_technology (boolean), category_name (best primary category if true, else null), category_confidence, confidence (overall 0.0-1.0), and reason (short string). A legal technology company is a market-facing vendor whose principal business is software, data, or technology-enabled services for legal work."
    }.to_json
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
