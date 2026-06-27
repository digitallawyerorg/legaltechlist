class CompanyProposalTaxonomySuggestionService
  HIGH_CONFIDENCE = 0.8

  CATEGORY_RULES = [
    ["Contract Management", /\b(contract|clm|redlin|negotiat|agreement)\b/i],
    ["Litigation & Dispute Resolution", /\b(litigation|dispute|case|court|claims?)\b/i],
    ["Compliance & Risk", /\b(compliance|regulatory|risk|policy|audit)\b/i],
    ["Document Management and Automation", /\b(document|automation|workflow|intake)\b/i],
    ["Document Management", /\b(document|automation|workflow|intake)\b/i],
    ["Knowledge & Research", /\b(research|knowledge|search|retrieval|rag)\b/i],
    ["Legal Research", /\b(research|knowledge|search|retrieval|rag)\b/i],
    ["Practice Management", /\b(practice management|matter|billing|operations)\b/i],
    ["IP Management", /\b(ip|intellectual property|patent|trademark)\b/i],
    ["Marketplace and ALSPs", /\b(marketplace|alsp|legal service|service provider)\b/i]
  ].freeze

  BUSINESS_MODEL_RULES = [
    ["SaaS", /\b(saas|software|platform|subscription|cloud)\b/i],
    ["Subscription", /\b(subscription|saas)\b/i],
    ["Legal Service Using Tech", /\b(service|managed|provider|alsp)\b/i]
  ].freeze

  TARGET_CLIENT_RULES = [
    ["Corporate Legal", /\b(in-house|corporate legal|legal department|legal teams?|enterprise)\b/i],
    ["Companies", /\b(in-house|corporate legal|legal department|legal teams?|enterprise|companies)\b/i],
    ["Law Firms", /\b(law firms?|lawyers?|attorneys?|litigation lawyers?)\b/i]
  ].freeze

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(source_payload:, final_changes: {})
    @source_payload = source_payload || {}
    @final_changes = final_changes || {}
  end

  def call
    suggestions = llm_suggestions.presence || deterministic_suggestions
    mapped = {
      "category" => map_suggestion(Category, suggestions["category_name"], suggestions["category_confidence"], "category_id"),
      "business_model" => map_suggestion(BusinessModel, suggestions["business_model_name"], suggestions["business_model_confidence"], "business_model_id"),
      "target_client" => map_suggestion(TargetClient, suggestions["target_client_name"], suggestions["target_client_confidence"], "target_client_id")
    }

    mapped.merge(
      "accepted" => mapped.values.all? { |suggestion| suggestion["accepted"] },
      "mode" => suggestions["mode"],
      "evidence" => evidence_text.truncate(500)
    )
  end

  private

  attr_reader :source_payload, :final_changes

  def deterministic_suggestions
    {
      "category_name" => matched_name(CATEGORY_RULES),
      "category_confidence" => matched_name(CATEGORY_RULES).present? ? 0.85 : 0.0,
      "business_model_name" => matched_name(BUSINESS_MODEL_RULES),
      "business_model_confidence" => matched_name(BUSINESS_MODEL_RULES).present? ? 0.85 : 0.0,
      "target_client_name" => matched_name(TARGET_CLIENT_RULES),
      "target_client_confidence" => matched_name(TARGET_CLIENT_RULES).present? ? 0.85 : 0.0,
      "mode" => "deterministic_rules"
    }
  end

  def llm_suggestions
    return unless llm_enabled?

    chat = RubyLLM.chat(model: llm_model, provider: :openai, assume_model_exists: true)
    parsed = JSON.parse(chat.ask(llm_prompt).content.to_s)
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

  def llm_prompt
    {
      candidate: source_payload.slice("name", "industries", "source_description", "full_source_description", "website"),
      allowed_category_names: Category.order(:name).pluck(:name),
      allowed_business_model_names: BusinessModel.order(:name).pluck(:name),
      allowed_target_client_names: TargetClient.order(:name).pluck(:name),
      instruction: "Return JSON with category_name, category_confidence, business_model_name, business_model_confidence, target_client_name, target_client_confidence. Use only allowed names. Confidence must be 0.0-1.0."
    }.to_json
  end

  def matched_name(rules)
    rules.find { |name, matcher| taxonomy_name_available?(name) && evidence_text.match?(matcher) }&.first
  end

  def taxonomy_name_available?(name)
    Category.exists?(name: name) || BusinessModel.exists?(name: name) || TargetClient.exists?(name: name)
  end

  def map_suggestion(model, name, confidence, field)
    record = model.find_by(name: name)
    value = final_changes[field].presence
    confidence_value = confidence.to_f

    if value.present?
      record = model.find_by(id: value)
      confidence_value = 1.0 if record.present?
    end

    {
      "id" => record&.id,
      "name" => record&.name || name,
      "confidence" => confidence_value,
      "accepted" => record.present? && confidence_value >= HIGH_CONFIDENCE
    }
  end

  def evidence_text
    @evidence_text ||= [
      final_changes["name"],
      final_changes["description"],
      source_payload["name"],
      source_payload["website"],
      Array(source_payload["industries"]).join(" "),
      source_payload["source_description"],
      source_payload["full_source_description"]
    ].compact.join(" ").squish
  end
end
