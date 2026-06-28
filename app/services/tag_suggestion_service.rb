require "timeout"

class TagSuggestionService
  HIGH_CONFIDENCE = 0.65
  MAX_TAGS = 5

  def self.call(company:, dry_run: true, min_confidence: nil, max_tags: MAX_TAGS)
    new(company: company, dry_run: dry_run, min_confidence: min_confidence, max_tags: max_tags).call
  end

  def initialize(company:, dry_run: true, min_confidence: nil, max_tags: MAX_TAGS)
    @company = company
    @dry_run = dry_run
    @min_confidence = min_confidence || default_min_confidence
    @max_tags = max_tags
  end

  def call
    return skip("already_tagged") if company.tags.any?
    return skip("human_reviewed") if company.human_reviewed_at.present? && !allow_human_reviewed_tags?

    keyword_result = CompanyTagBackfillService.call(company: company, dry_run: dry_run, max_tags: max_tags)
    return keyword_result if keyword_result["action"].in?(%w[tagged would_tag])

    return skip("llm_disabled") unless llm_enabled?

    suggestion = llm_suggestion
    names = Array(suggestion["tag_names"]).map { |name| TagNormalizationService.canonical_name(name) }.compact.uniq.first(max_tags)
    confidence = suggestion["confidence"].to_f
    return skip("no_suggestion", names, confidence, suggestion["mode"]) if names.empty?
    return skip("low_confidence", names, confidence, suggestion["mode"]) if confidence < min_confidence

    unless dry_run
      company.tags = names.filter_map { |name| TagNormalizationService.find_or_create_canonical(name) }
    end

    {
      "company_id" => company.id,
      "company_name" => company.name,
      "suggested_tags" => names,
      "confidence" => confidence,
      "mode" => suggestion["mode"],
      "action" => dry_run ? "would_tag" : "tagged"
    }
  end

  private

  attr_reader :company, :dry_run, :min_confidence, :max_tags

  def default_min_confidence
    return AUTO_CONFIDENCE if ENV.fetch("AUTO_HYGIENE", "false") == "true"

    ENV.fetch("MIN_CONFIDENCE", HIGH_CONFIDENCE.to_s).to_f
  end

  AUTO_CONFIDENCE = 0.55

  def llm_suggestion
    chat = RubyLLM.chat(model: llm_model, provider: :openai, assume_model_exists: true)
    response = Timeout.timeout(llm_timeout_seconds) { chat.ask(llm_prompt) }
    parsed = JSON.parse(response.content.to_s)
    parsed.merge("mode" => "ruby_llm")
  rescue StandardError
    { "tag_names" => [], "confidence" => 0.0, "mode" => "ruby_llm_error" }
  end

  def llm_enabled?
    defined?(RubyLLM) &&
      ENV["OPENAI_API_KEY"].present? &&
      ENV.fetch("TAG_SUGGESTION_USE_LLM", ENV.fetch("PROPOSAL_TAXONOMY_USE_LLM", Rails.env.production? ? "true" : "false")) == "true"
  end

  def llm_model
    ENV.fetch("RUBYLLM_TAXONOMY_MODEL", ENV.fetch("RUBYLLM_HARD_MODEL", "gpt-5.5"))
  end

  def llm_timeout_seconds
    ENV.fetch("TAG_SUGGESTION_TIMEOUT_SECONDS", ENV.fetch("PROPOSAL_TAXONOMY_TIMEOUT_SECONDS", "45")).to_i
  end

  def llm_prompt
    {
      company: {
        name: company.name,
        website: company.main_url,
        description: effective_description,
        category: company.category&.name,
        target_clients: company.audience_names
      },
      preferred_tag_vocabulary: preferred_tag_vocabulary,
      instruction: "Return JSON with tag_names (array of 1-#{max_tags} lowercase technology or theme keywords for this legal-technology company) and confidence (0.0-1.0). Prefer preferred_tag_vocabulary terms when they fit. Use generic legal-tech themes only when supported by the company profile."
    }.to_json
  end

  def preferred_tag_vocabulary
    path = Rails.root.join("config/taxonomy/tag_aliases.yml")
    data = YAML.safe_load(File.read(path), permitted_classes: [], aliases: true) || {}
    data.keys.map { |name| TagNormalizationService.normalize_name(name) }.uniq.sort
  end

  def effective_description
    text = company.description.to_s.strip
    return nil if text.blank? || text == "No description yet"

    text
  end

  def allow_human_reviewed_tags?
    ENV.fetch("ALLOW_HUMAN_REVIEWED_TAGS", "false") == "true"
  end

  def skip(reason, suggested_tags = nil, confidence = nil, mode = nil)
    {
      "company_id" => company.id,
      "company_name" => company.name,
      "suggested_tags" => suggested_tags,
      "confidence" => confidence,
      "mode" => mode,
      "action" => "skipped_#{reason}"
    }
  end
end
