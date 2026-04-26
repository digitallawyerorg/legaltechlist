class DescriptionDraftAgent
  MARKETING_TERMS = %w[
    best
    cutting-edge
    game-changing
    leading
    revolutionary
    world-class
  ].freeze

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

    {
      "agent" => self.class.name,
      "company_id" => company.id,
      "generated_at" => Time.current.utc.iso8601,
      "mode" => draft_payload.fetch("mode"),
      "model" => draft_payload["model"],
      "proposed_description" => sanitize_description(draft_payload.fetch("proposed_description")),
      "rationale" => draft_payload["rationale"],
      "confidence" => draft_payload["confidence"],
      "source_limits" => source_limits,
      "warnings" => warnings(draft_payload.fetch("proposed_description"))
    }
  rescue StandardError => e
    fallback_draft.merge(
      "agent" => self.class.name,
      "company_id" => company.id,
      "generated_at" => Time.current.utc.iso8601,
      "mode" => "fallback_after_error",
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
    model = ENV.fetch("RUBYLLM_DESCRIPTION_MODEL", ENV.fetch("RUBYLLM_DEFAULT_MODEL", "gpt-5-nano"))
    chat = RubyLLM.chat(model: model)
      .with_temperature(0.2)
      .with_params(response_format: { type: "json_object" })

    chat.with_instructions(description_instructions)
    response = chat.ask(description_prompt)
    parsed = parse_json_content(response.content)

    {
      "mode" => "ruby_llm",
      "model" => model,
      "proposed_description" => parsed["proposed_description"],
      "rationale" => parsed["rationale"],
      "confidence" => parsed["confidence"]
    }
  end

  def fallback_draft
    description = "#{company.name} is listed in TechIndex as a legal technology company"
    description += " in the #{company.category.name} category" if company.category&.name.present?
    description += " with a #{company.business_model.name.downcase} business model" if company.business_model&.name.present?
    description += " serving #{company.target_client.name.downcase}" if company.target_client&.name.present?
    description += "."

    {
      "mode" => "deterministic_fallback",
      "model" => nil,
      "proposed_description" => description,
      "rationale" => "Generated from current TechIndex taxonomy fields only because model-backed drafting was unavailable or disabled.",
      "confidence" => "low"
    }
  end

  def parse_json_content(content)
    return content if content.is_a?(Hash)

    JSON.parse(content.to_s)
  rescue JSON::ParserError
    { "proposed_description" => content.to_s, "rationale" => "Model returned non-JSON content.", "confidence" => "low" }
  end

  def description_instructions
    <<~TEXT
      You draft neutral academic directory descriptions for Stanford CodeX TechIndex.
      Return only JSON with keys: proposed_description, rationale, confidence.
      The proposed_description must be one sentence, 25 to 45 words, objective, factual, and non-marketing.
      Do not copy or lightly rewrite source/current descriptions.
      Do not use superlatives or claims such as leading, best, revolutionary, cutting-edge, world-class, or game-changing.
      If facts are thin, write conservatively and say the company is listed in TechIndex as operating in the known category.
    TEXT
  end

  def description_prompt
    {
      company: {
        name: company.name,
        current_description: company.description,
        website: company.main_url,
        category: company.category&.name,
        business_model: company.business_model&.name,
        target_client: company.target_client&.name,
        status: company.status
      },
      evidence: Array(evidence_payload["evidence"]),
      evidence_gaps: Array(evidence_payload["evidence_gaps"]),
      verification: verification_payload.slice("verdict", "quality_score", "risks", "taxonomy_signals")
    }.to_json
  end

  def sanitize_description(description)
    cleaned = description.to_s.squish
    MARKETING_TERMS.each do |term|
      cleaned = cleaned.gsub(/\b#{Regexp.escape(term)}\b/i, "")
    end
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
    flagged
  end

  def marketing_language?(description)
    text = description.to_s.downcase
    MARKETING_TERMS.any? { |term| text.include?(term) }
  end
end
