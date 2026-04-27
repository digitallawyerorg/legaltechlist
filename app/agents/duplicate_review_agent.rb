class DuplicateReviewAgent < RubyLLM::Agent
  RELATIONSHIPS = %w[duplicate rebrand related distinct].freeze
  OVERALL_RECOMMENDATIONS = %w[
    needs_human_review
    likely_duplicate_group
    likely_rebrand_group
    related_entities
    likely_distinct
  ].freeze

  model "gpt-5.5"
  instructions
  schema DuplicateReviewSchema
  temperature 0.1

  SCHEMA_VERSION = DuplicateReviewSchema::SCHEMA_VERSION

  def self.call(company, candidates:)
    new(company, candidates: candidates).call
  end

  def initialize(company, candidates:)
    @company = company
    @candidates = Array(candidates)
  end

  def call
    review_payload = llm_enabled? ? llm_review : deterministic_review

    {
      "agent" => self.class.name,
      "company_id" => company.id,
      "generated_at" => Time.current.utc.iso8601,
      "schema" => "DuplicateReviewSchema",
      "schema_version" => SCHEMA_VERSION,
      "mode" => review_payload.fetch("mode"),
      "model" => review_payload["model"],
      "overall_recommendation" => normalized_overall(review_payload["overall_recommendation"]),
      "pair_reviews" => normalize_pair_reviews(review_payload["pair_reviews"]),
      "unresolved_questions" => Array(review_payload["unresolved_questions"]),
      "rationale" => review_payload["rationale"],
      "confidence" => review_payload["confidence"].presence || "low",
      "usage" => review_payload["usage"],
      "estimated_cost_usd" => review_payload["estimated_cost_usd"]
    }
  rescue StandardError => e
    deterministic_review.merge(
      "agent" => self.class.name,
      "company_id" => company.id,
      "generated_at" => Time.current.utc.iso8601,
      "schema" => "DuplicateReviewSchema",
      "schema_version" => SCHEMA_VERSION,
      "mode" => "fallback_after_error",
      "error_class" => e.class.name,
      "error_message" => e.message
    )
  end

  private

  attr_reader :company, :candidates

  def llm_enabled?
    defined?(RubyLLM) &&
      ENV["OPENAI_API_KEY"].present? &&
      ENV.fetch("DUPLICATE_REVIEWS_USE_LLM", ENV.fetch("DESCRIPTION_DRAFTS_USE_LLM", "true")) == "true"
  end

  def llm_review
    model = hard_model
    chat = self.class.chat(model: model, provider: :openai, assume_model_exists: unknown_model?(model))
    response = chat.ask(review_prompt)
    parsed = parse_json_content(response.content)

    {
      "mode" => "ruby_llm",
      "model" => response.model_id.presence || model,
      "overall_recommendation" => parsed["overall_recommendation"],
      "pair_reviews" => parsed["pair_reviews"],
      "unresolved_questions" => parsed["unresolved_questions"],
      "rationale" => parsed["rationale"],
      "confidence" => parsed["confidence"],
      "usage" => usage_payload(response),
      "estimated_cost_usd" => estimated_cost(response)
    }
  end

  def deterministic_review
    pair_reviews = candidates.map { |candidate| deterministic_pair_review(candidate) }
    relationships = pair_reviews.map { |review| review["relationship"] }
    overall = if relationships.include?("duplicate")
      "likely_duplicate_group"
    elsif relationships.include?("rebrand")
      "likely_rebrand_group"
    elsif relationships.include?("related")
      "related_entities"
    elsif relationships.present?
      "likely_distinct"
    else
      "needs_human_review"
    end

    {
      "mode" => "deterministic_fallback",
      "model" => nil,
      "overall_recommendation" => overall,
      "pair_reviews" => pair_reviews,
      "unresolved_questions" => pair_reviews.any? ? ["Confirm relationship manually before merging, deleting, hiding, or overwriting either record."] : ["No duplicate candidates were available for comparison."],
      "rationale" => "Deterministic duplicate review compared normalized names and canonical domains only.",
      "confidence" => deterministic_confidence(pair_reviews),
      "usage" => nil,
      "estimated_cost_usd" => nil
    }
  end

  def deterministic_pair_review(candidate)
    same_name = company.normalized_name.present? && company.normalized_name == candidate.normalized_name
    same_domain = canonical_domain(company).present? && canonical_domain(company) == canonical_domain(candidate)
    relationship = if same_name && same_domain
      "duplicate"
    elsif same_domain
      "related"
    elsif same_name
      "related"
    else
      "distinct"
    end

    {
      "company_id" => company.id,
      "candidate_company_id" => candidate.id,
      "relationship" => relationship,
      "confidence" => same_name && same_domain ? "medium" : "low",
      "reasons" => deterministic_reasons(candidate, same_name: same_name, same_domain: same_domain),
      "recommended_actions" => recommended_actions_for(relationship)
    }
  end

  def deterministic_reasons(candidate, same_name:, same_domain:)
    reasons = []
    reasons << "Normalized names match." if same_name
    reasons << "Canonical domains match." if same_domain
    reasons << "Names and canonical domains do not match." unless same_name || same_domain
    reasons << "Primary record: #{company.name} (#{canonical_domain(company).presence || 'missing domain'})."
    reasons << "Candidate record: #{candidate.name} (#{canonical_domain(candidate).presence || 'missing domain'})."
    reasons
  end

  def recommended_actions_for(relationship)
    case relationship
    when "duplicate" then ["Human reviewer should compare records side by side before any merge decision."]
    when "rebrand" then ["Human reviewer should verify successor or former-name evidence before updating names or URLs."]
    when "related" then ["Human reviewer should determine whether records are parent/product/regional pages or distinct companies."]
    else ["Human reviewer should leave records separate unless stronger evidence appears."]
    end
  end

  def deterministic_confidence(pair_reviews)
    return "low" if pair_reviews.blank?
    return "medium" if pair_reviews.any? { |review| review["relationship"] == "duplicate" && review["confidence"] == "medium" }

    "low"
  end

  def review_prompt
    {
      primary_company: company_payload(company),
      candidate_companies: candidates.map { |candidate| company_payload(candidate) },
      instructions: {
        no_public_writes: true,
        no_auto_merge: true,
        preserve_uncertainty: true
      }
    }.to_json
  end

  def company_payload(record)
    {
      id: record.id,
      name: record.name,
      normalized_name: record.normalized_name,
      description: record.description,
      main_url: record.main_url,
      canonical_domain: canonical_domain(record),
      category: record.category&.name,
      business_model: record.business_model&.name,
      target_client: record.target_client&.name,
      visible: record.visible,
      quality_status: record.quality_status
    }
  end

  def canonical_domain(record)
    record.canonical_domain.presence || record.canonical_main_domain
  end

  def parse_json_content(content)
    return content if content.is_a?(Hash)

    JSON.parse(content.to_s)
  rescue JSON::ParserError
    { "overall_recommendation" => "needs_human_review", "pair_reviews" => [], "unresolved_questions" => ["Model returned non-JSON content."], "rationale" => "Structured duplicate review could not be parsed.", "confidence" => "low" }
  end

  def normalized_overall(value)
    OVERALL_RECOMMENDATIONS.include?(value) ? value : "needs_human_review"
  end

  def normalize_pair_reviews(values)
    Array(values).map do |review|
      review = review.to_h
      review.merge(
        "company_id" => review["company_id"].to_i,
        "candidate_company_id" => review["candidate_company_id"].to_i,
        "relationship" => RELATIONSHIPS.include?(review["relationship"]) ? review["relationship"] : "related",
        "confidence" => %w[low medium high].include?(review["confidence"]) ? review["confidence"] : "low",
        "reasons" => Array(review["reasons"]),
        "recommended_actions" => Array(review["recommended_actions"])
      )
    end
  end

  def hard_model
    ENV.fetch("RUBYLLM_DUPLICATE_MODEL", ENV.fetch("RUBYLLM_HARD_MODEL", "gpt-5.5"))
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
end
