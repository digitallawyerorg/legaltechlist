class DescriptionDraftAgent < RubyLLM::Agent
  model "gpt-5.5"
  instructions
  schema DescriptionDraftSchema
  temperature 0.2

  MARKETING_TERMS = %w[
    best
    cutting-edge
    game-changing
    leading
    revolutionary
    world-class
  ].freeze

  SCHEMA_VERSION = DescriptionDraftSchema::SCHEMA_VERSION

  def self.call(company, evidence_payload:, verification_payload:)
    new(company, evidence_payload: evidence_payload, verification_payload: verification_payload).call
  end

  def initialize(company, evidence_payload:, verification_payload:)
    @company = company
    @evidence_payload = evidence_payload
    @verification_payload = verification_payload
  end

  def call
    draft_payload = llm_enabled? ? llm_draft : fallback_draft
    proposed_description = sanitize_description(draft_payload.fetch("proposed_description"))

    {
      "agent" => self.class.name,
      "company_id" => company.id,
      "generated_at" => Time.current.utc.iso8601,
      "schema" => "DescriptionDraftSchema",
      "schema_version" => SCHEMA_VERSION,
      "mode" => draft_payload.fetch("mode"),
      "model" => draft_payload["model"],
      "proposed_description" => proposed_description,
      "rationale" => draft_payload["rationale"],
      "confidence" => draft_payload["confidence"],
      "usage" => draft_payload["usage"],
      "estimated_cost_usd" => draft_payload["estimated_cost_usd"],
      "source_limits" => source_limits,
      "warnings" => warnings(proposed_description)
    }
  rescue StandardError => e
    draft_payload = fallback_draft
    proposed_description = sanitize_description(draft_payload.fetch("proposed_description"))

    draft_payload.merge(
      "agent" => self.class.name,
      "company_id" => company.id,
      "generated_at" => Time.current.utc.iso8601,
      "schema" => "DescriptionDraftSchema",
      "schema_version" => SCHEMA_VERSION,
      "mode" => "fallback_after_error",
      "source_limits" => source_limits,
      "warnings" => warnings(proposed_description),
      "error_class" => e.class.name,
      "error_message" => e.message
    )
  end

  private

  attr_reader :company, :evidence_payload, :verification_payload

  def llm_enabled?
    defined?(RubyLLM) &&
      ENV["OPENAI_API_KEY"].present? &&
      ENV.fetch("DESCRIPTION_DRAFTS_USE_LLM", "true") == "true"
  end

  def llm_draft
    model = hard_model
    chat = self.class.chat(model: model, provider: :openai, assume_model_exists: unknown_model?(model))
    response = chat.ask(description_prompt)
    parsed = parse_json_content(response.content)

    {
      "mode" => "ruby_llm",
      "model" => response.model_id.presence || model,
      "proposed_description" => parsed["proposed_description"],
      "rationale" => parsed["rationale"],
      "confidence" => parsed["confidence"],
      "usage" => usage_payload(response),
      "estimated_cost_usd" => estimated_cost(response)
    }
  end

  def fallback_draft
    segments = []
    segments << "in #{company.category.name}" if company.category&.name.present?
    segments << "with #{company.revenue_model_names.map(&:downcase).to_sentence} revenue" if company.revenue_model_names.any?
    segments << "serving #{company.target_client.name.downcase}" if company.target_client&.name.present?
    description = if segments.any?
      "#{company.name} provides or supports legal technology #{segments.to_sentence}."
    else
      "#{company.name} provides or supports legal technology services."
    end

    {
      "mode" => "deterministic_fallback",
      "model" => nil,
      "proposed_description" => description,
      "rationale" => "Generated from current TechIndex taxonomy fields only because model-backed drafting was unavailable or disabled.",
      "confidence" => "low",
      "usage" => nil,
      "estimated_cost_usd" => nil
    }
  end

  def parse_json_content(content)
    return content if content.is_a?(Hash)

    JSON.parse(content.to_s)
  rescue JSON::ParserError
    { "proposed_description" => content.to_s, "rationale" => "Model returned non-JSON content.", "confidence" => "low" }
  end

  def hard_model
    ENV.fetch("RUBYLLM_DESCRIPTION_MODEL", ENV.fetch("RUBYLLM_HARD_MODEL", "gpt-5.5"))
  end

  def unknown_model?(model)
    RubyLLM.models.find(model)
    false
  rescue RubyLLM::ModelNotFoundError
    true
  end

  def description_prompt
    {
      company: {
        name: company.name,
        current_description: company.description,
        website: company.main_url,
        category: company.category&.name,
        revenue_models: company.revenue_model_names,
        target_client: company.target_client&.name,
        status: company.status
      },
      evidence: Array(evidence_payload["evidence"]),
      evidence_tools: evidence_payload["tool_results"] || {},
      evidence_gaps: Array(evidence_payload["evidence_gaps"]),
      verification: verification_payload.slice("verdict", "quality_score", "risks", "taxonomy_signals")
    }.to_json
  end

  def usage_payload(response)
    {
      "input_tokens" => response.input_tokens,
      "output_tokens" => response.output_tokens,
      "cached_tokens" => response.cached_tokens,
      "cache_creation_tokens" => response.cache_creation_tokens,
      "thinking_tokens" => response.thinking_tokens,
      "total_tokens" => [response.input_tokens, response.output_tokens].compact.sum
    }
  end

  def estimated_cost(response)
    model_info = RubyLLM.models.find(response.model_id)
    return unless model_info&.input_price_per_million && model_info&.output_price_per_million

    input_tokens = response.input_tokens.to_i
    output_tokens = response.output_tokens.to_i
    input_cost = input_tokens * model_info.input_price_per_million / 1_000_000.0
    output_cost = output_tokens * model_info.output_price_per_million / 1_000_000.0
    (input_cost + output_cost).round(8)
  rescue StandardError
    nil
  end

  def sanitize_description(description)
    cleaned = description.to_s.squish
    MARKETING_TERMS.each do |term|
      cleaned = cleaned.gsub(/\b#{Regexp.escape(term)}\b/i, "")
    end
    cleaned = cleaned.gsub(/\b(?:is\s+)?(?:listed|included)\s+in\s+TechIndex\s+as\s+/i, "")
    cleaned = cleaned.gsub(/\ba\s+TechIndex\s+company\b/i, "a legal technology company")
    cleaned = cleaned.gsub(/\b(?:based on|according to|identified in)\s+(?:available records|directory metadata|stored profiles|the current record|the current TechIndex record)\b/i, "")
    cleaned = cleaned.gsub(/\b(?:through|via)\s+its\s+[\w.-]+\s+domain\b/i, "")
    cleaned = cleaned.gsub(/\b(?:associated with|connected to)\s+(?:the\s+)?(?:website|domain|social profiles?)\b/i, "")
    cleaned.squish
  end

  def source_limits
    [
      "Draft is stored as a proposal only.",
      "Source descriptions must not be copied into public TechIndex text.",
      "Human review is required before publication."
    ]
  end

  def warnings(description)
    flagged = []
    flagged << "Draft is shorter than expected." if description.to_s.squish.split.size < 20
    flagged << "Draft may contain marketing language." if marketing_language?(description)
    flagged << "Draft describes TechIndex rather than the company." if directory_meta_language?(description)
    flagged << "Draft may describe source metadata rather than company facts." if source_meta_language?(description)
    flagged
  end

  def marketing_language?(description)
    text = description.to_s.downcase
    MARKETING_TERMS.any? { |term| text.include?(term) }
  end

  def directory_meta_language?(description)
    description.to_s.match?(/\b(listed in TechIndex|included in TechIndex|TechIndex company)\b/i)
  end

  def source_meta_language?(description)
    description.to_s.match?(/\b(available records|directory metadata|stored profiles|associated social profiles|primary web presence|current record|through its [\w.-]+ domain|associated with the website)\b/i)
  end
end
