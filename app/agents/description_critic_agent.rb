class DescriptionCriticAgent < RubyLLM::Agent
  model "gpt-5.5"
  instructions
  schema DescriptionCriticSchema
  temperature 0.1

  MARKETING_TERMS = DescriptionDraftAgent::MARKETING_TERMS
  SCHEMA_VERSION = DescriptionCriticSchema::SCHEMA_VERSION

  def self.call(company, evidence_payload:, verification_payload:, description_payload:)
    new(company, evidence_payload: evidence_payload, verification_payload: verification_payload, description_payload: description_payload).call
  end

  def initialize(company, evidence_payload:, verification_payload:, description_payload:)
    @company = company
    @evidence_payload = evidence_payload
    @verification_payload = verification_payload
    @description_payload = description_payload
  end

  def call
    critique_payload = llm_enabled? ? llm_critique : deterministic_critique

    {
      "agent" => self.class.name,
      "company_id" => company.id,
      "generated_at" => Time.current.utc.iso8601,
      "schema" => "DescriptionCriticSchema",
      "schema_version" => SCHEMA_VERSION,
      "mode" => critique_payload.fetch("mode"),
      "model" => critique_payload["model"],
      "verdict" => critique_payload["verdict"],
      "issues" => Array(critique_payload["issues"]),
      "rationale" => critique_payload["rationale"],
      "suggested_revision" => critique_payload["suggested_revision"],
      "confidence" => critique_payload["confidence"],
      "usage" => critique_payload["usage"],
      "estimated_cost_usd" => critique_payload["estimated_cost_usd"]
    }
  rescue StandardError => e
    deterministic_critique.merge(
      "agent" => self.class.name,
      "company_id" => company.id,
      "generated_at" => Time.current.utc.iso8601,
      "schema" => "DescriptionCriticSchema",
      "schema_version" => SCHEMA_VERSION,
      "mode" => "fallback_after_error",
      "error_class" => e.class.name,
      "error_message" => e.message
    )
  end

  private

  attr_reader :company, :evidence_payload, :verification_payload, :description_payload

  def llm_enabled?
    defined?(RubyLLM) &&
      ENV["OPENAI_API_KEY"].present? &&
      ENV.fetch("DESCRIPTION_CRITIC_USE_LLM", ENV.fetch("DESCRIPTION_DRAFTS_USE_LLM", "true")) == "true"
  end

  def llm_critique
    model = hard_model
    chat = self.class.chat(model: model, provider: :openai, assume_model_exists: unknown_model?(model))
    response = chat.ask(critique_prompt)
    parsed = parse_json_content(response.content)

    {
      "mode" => "ruby_llm",
      "model" => response.model_id.presence || model,
      "verdict" => parsed["verdict"],
      "issues" => parsed["issues"],
      "rationale" => parsed["rationale"],
      "suggested_revision" => parsed["suggested_revision"],
      "confidence" => parsed["confidence"],
      "usage" => usage_payload(response),
      "estimated_cost_usd" => estimated_cost(response)
    }
  end

  def deterministic_critique
    issues = deterministic_issues
    verdict = issues.any? ? "revise" : "pass"

    {
      "mode" => "deterministic_fallback",
      "model" => nil,
      "verdict" => verdict,
      "issues" => issues,
      "rationale" => issues.any? ? "Deterministic checks found description quality issues requiring human review." : "No deterministic description quality issues were found.",
      "suggested_revision" => issues.any? ? fallback_revision.to_s : "",
      "confidence" => issues.any? ? "medium" : "low",
      "usage" => nil,
      "estimated_cost_usd" => nil
    }
  end

  def deterministic_issues
    description = proposed_description
    issues = []
    issues << "Description uses directory-meta phrasing rather than describing the company." if directory_meta_language?(description)
    issues << "Description contains marketing language or superlatives." if marketing_language?(description)
    issues << "Description is shorter than expected for public review." if description.split.size < 20
    issues << "Description references weak or indirect evidence instead of company facts." if weak_evidence_language?(description)
    issues
  end

  def fallback_revision
    category = company.category&.name
    target_client = company.target_client&.name&.downcase
    return "#{company.name} provides or supports legal technology in #{category} for #{target_client}." if category.present? && target_client.present?
    return "#{company.name} provides or supports legal technology in #{category}." if category.present?
    return "#{company.name} provides or supports legal technology for #{target_client}." if target_client.present?

    nil
  end

  def critique_prompt
    {
      company: {
        name: company.name,
        current_description: company.description,
        website: company.main_url,
        category: company.category&.name,
        business_model: company.business_model&.name,
        target_client: company.target_client&.name
      },
      proposed_description: proposed_description,
      draft_rationale: description_payload["rationale"],
      draft_warnings: Array(description_payload["warnings"]),
      evidence: Array(evidence_payload["evidence"]),
      evidence_gaps: Array(evidence_payload["evidence_gaps"]),
      verification: verification_payload.slice("verdict", "quality_score", "risks", "taxonomy_signals")
    }.to_json
  end

  def proposed_description
    description_payload["proposed_description"].to_s.squish
  end

  def parse_json_content(content)
    return content if content.is_a?(Hash)

    JSON.parse(content.to_s)
  rescue JSON::ParserError
    { "verdict" => "revise", "issues" => ["Model returned non-JSON content."], "rationale" => "Structured critique could not be parsed.", "confidence" => "low" }
  end

  def hard_model
    ENV.fetch("RUBYLLM_CRITIC_MODEL", ENV.fetch("RUBYLLM_HARD_MODEL", "gpt-5.5"))
  end

  def unknown_model?(model)
    RubyLLM.models.find(model)
    false
  rescue RubyLLM::ModelNotFoundError
    true
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

  def directory_meta_language?(description)
    description.match?(/\b(listed in TechIndex|included in TechIndex|TechIndex company|directory metadata|available directory|available records)\b/i)
  end

  def weak_evidence_language?(description)
    description.match?(/\b(based on available|associated social profiles|directory metadata|current TechIndex record)\b/i)
  end

  def marketing_language?(description)
    text = description.downcase
    MARKETING_TERMS.any? { |term| text.include?(term) }
  end
end
