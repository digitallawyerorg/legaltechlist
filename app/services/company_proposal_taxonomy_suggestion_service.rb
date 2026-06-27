require "timeout"

class CompanyProposalTaxonomySuggestionService
  HIGH_CONFIDENCE = 0.8

  CATEGORY_RULES = [
    ["eDiscovery & Investigations", /\b(ediscovery|e-discovery|electronically stored information|\besi\b|digital forensics|forensic)\b/i],
    ["Legal Operations / ELM", /\b(legal operations|matter management|e-?billing|enterprise legal management|\belm\b|legal spend)\b/i],
    ["Access to Justice & Public Sector", /\b(access to justice|legal aid|pro bono|self-represented|pro se|court self-help)\b/i],
    ["Analytics & Insights", /\b(analytics?|insights?|metrics?|dashboard|reporting|benchmark|intelligence|data analysis|trend)\b/i],
    ["Contract Management", /\b(contract|clm|redlin|negotiat|agreement)\b/i],
    ["Litigation & Dispute Resolution", /\b(litigation|dispute|case|court|claims?)\b/i],
    ["Compliance & Risk", /\b(compliance|regulatory|risk|policy|audit)\b/i],
    ["Document Management and Automation", /\b(document|automation|workflow|intake)\b/i],
    ["Knowledge & Research", /\b(research|knowledge|search|retrieval|rag)\b/i],
    ["Practice Management", /\b(practice management|calendaring|time tracking|client intake)\b/i],
    ["IP Management", /\b(ip|intellectual property|patent|trademark)\b/i],
    ["Marketplace and ALSPs", /\b(marketplace|alsp|legal service|service provider)\b/i]
  ].freeze

  REVENUE_MODEL_RULES = [
    ["Subscription", /\b(subscription|saas|recurring|seat-based|tiered|cloud platform|software platform|legal tech)\b/i],
    ["Usage-Based", /\b(usage-based|consumption|api calls|storage|compute|pay as you go|per unit)\b/i],
    ["Transaction Fee", /\b(transaction fee|commission|take rate|marketplace fee|payment processing)\b/i],
    ["Services", /\b(managed service|outsourc|consulting|retainer|hourly|staffing|alsp)\b/i],
    ["Licensing", /\b(licensing|license fee|royalt|ip licensing)\b/i],
    ["Advertising", /\b(advertising|ads|sponsorship)\b/i],
    ["Commerce", /\b(commerce|one-time|product sales|ecommerce)\b/i],
    ["Success Fee", /\b(success fee|contingency|performance-based|recruiting fee)\b/i],
    ["Grants & Subsidies", /\b(grant-funded|grants?|donations?|subsid(y|ies)|philanthrop|501\(c\)|nonprofit|non-profit|legal aid|legal services corporation|lsc\b|iolta|publicly funded|government funded|foundation support)\b/i]
  ].freeze

  TARGET_CLIENT_RULES = [
    ["Corporate Legal", /\b(in-house|corporate legal|legal departments?|legal operations|general counsel)\b/i],
    ["Law Firms", /\b(law firms?|lawyers?|attorneys?|litigation lawyers?|legal professionals?)\b/i],
    ["Legal Service Providers", /\b(legal service providers?|alsp)\b/i],
    ["Government", /\b(government|public sector|agency|court|regulator)\b/i],
    ["Consumers", /\b(individuals?|consumers?|self-represented|pro se|b2c)\b/i],
    ["Corporate Legal", /\b(in-house|corporate legal|legal departments?|legal operations|general counsel|enterprise|businesses?|companies|organizations?|legal teams?)\b/i]
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
    revenue_models = map_revenue_models(suggestions["revenue_model_names"], suggestions["revenue_model_confidence"])

    mapped = {
      "category" => map_suggestion(Category, suggestions["category_name"], suggestions["category_confidence"], "category_id"),
      "revenue_models" => revenue_models.except("records"),
      "target_client" => map_suggestion(TargetClient, suggestions["target_client_name"], suggestions["target_client_confidence"], "target_client_id")
    }

    mapped.merge(
      "accepted" => mapped.values_at("category", "revenue_models", "target_client").all? { |suggestion| suggestion["accepted"] },
      "mode" => suggestions["mode"],
      "evidence" => evidence_text.truncate(500)
    )
  end

  private

  attr_reader :source_payload, :final_changes

  def deterministic_suggestions
    revenue_model_names = matched_revenue_model_names
    {
      "category_name" => matched_name(CATEGORY_RULES),
      "category_confidence" => matched_name(CATEGORY_RULES).present? ? 0.85 : 0.0,
      "revenue_model_names" => revenue_model_names,
      "revenue_model_confidence" => revenue_model_names.any? ? 0.85 : 0.0,
      "target_client_name" => matched_name(TARGET_CLIENT_RULES),
      "target_client_confidence" => matched_name(TARGET_CLIENT_RULES).present? ? 0.85 : 0.0,
      "mode" => "deterministic_rules"
    }
  end

  def llm_suggestions
    return unless llm_enabled?

    chat = RubyLLM.chat(model: llm_model, provider: :openai, assume_model_exists: true)
    response = Timeout.timeout(llm_timeout_seconds) { chat.ask(llm_prompt) }
    parsed = JSON.parse(response.content.to_s)
    parsed["revenue_model_names"] ||= Array(parsed["business_model_name"]).compact
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
      candidate: source_payload.slice("name", "industries", "source_description", "full_source_description", "website"),
      allowed_category_names: Category.order(:name).pluck(:name),
      allowed_revenue_model_names: MethodologyHelper::REVENUE_MODEL_NAMES,
      allowed_target_client_names: TaxonomyNormalizationService::CANONICAL_TARGET_CLIENTS,
      instruction: "Return JSON with category_name, category_confidence, revenue_model_names (array, 1-3 items from allowed list), revenue_model_confidence, target_client_name, target_client_confidence. Use only allowed names. Confidence must be 0.0-1.0."
    }.to_json
  end

  def matched_name(rules)
    rules.find { |name, matcher| taxonomy_name_available?(name) && evidence_text.match?(matcher) }&.first
  end

  def matched_revenue_model_names
    REVENUE_MODEL_RULES.filter_map do |name, matcher|
      name if MethodologyHelper::REVENUE_MODEL_NAMES.include?(name) && evidence_text.match?(matcher)
    end.uniq
  end

  def taxonomy_name_available?(name)
    Category.exists?(name: name) || MethodologyHelper::REVENUE_MODEL_NAMES.include?(name) || BusinessModel.exists?(name: name) || TargetClient.exists?(name: name)
  end

  def map_revenue_models(names, confidence)
    names = Array(names).map(&:to_s).reject(&:blank?).uniq
    if final_changes["business_model_ids"].present?
      records = BusinessModel.where(id: Array(final_changes["business_model_ids"]))
      confidence_value = 1.0
    else
      records = names.filter_map { |name| BusinessModel.find_by(name: name) }
      confidence_value = confidence.to_f
      confidence_value = 0.85 if confidence_value.zero? && records.any?
    end

    {
      "records" => records.to_a,
      "ids" => records.map(&:id),
      "names" => records.map(&:name),
      "confidence" => records.any? ? confidence_value : 0.0,
      "accepted" => records.any? && confidence_value >= HIGH_CONFIDENCE
    }
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
