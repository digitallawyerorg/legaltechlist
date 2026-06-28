class ReviewCoordinatorAgent < RubyLLM::Agent
  STATUSES = %w[
    ready_for_human_review
    needs_more_evidence
    needs_description_revision
    possible_duplicate
    do_not_publish
  ].freeze

  STATUS_PRIORITY = {
    "ready_for_human_review" => 0,
    "needs_description_revision" => 1,
    "needs_more_evidence" => 2,
    "possible_duplicate" => 3,
    "do_not_publish" => 4
  }.freeze

  model "gpt-5.5"
  instructions
  schema ReviewCoordinatorSchema
  temperature 0.1

  SCHEMA_VERSION = ReviewCoordinatorSchema::SCHEMA_VERSION

  def self.call(company, evidence_payload:, verification_payload:, description_payload:, critic_payload:)
    new(
      company,
      evidence_payload: evidence_payload,
      verification_payload: verification_payload,
      description_payload: description_payload,
      critic_payload: critic_payload
    ).call
  end

  def initialize(company, evidence_payload:, verification_payload:, description_payload:, critic_payload:)
    @company = company
    @evidence_payload = evidence_payload
    @verification_payload = verification_payload
    @description_payload = description_payload
    @critic_payload = critic_payload
  end

  def call
    coordination_payload = llm_enabled? ? llm_coordination : deterministic_coordination
    guarded_payload = apply_guardrails(coordination_payload)

    {
      "agent" => self.class.name,
      "company_id" => company.id,
      "generated_at" => Time.current.utc.iso8601,
      "schema" => "ReviewCoordinatorSchema",
      "schema_version" => SCHEMA_VERSION,
      "mode" => guarded_payload.fetch("mode"),
      "model" => guarded_payload["model"],
      "status" => guarded_payload["status"],
      "reasons" => Array(guarded_payload["reasons"]),
      "disagreements" => Array(guarded_payload["disagreements"]),
      "recommended_actions" => Array(guarded_payload["recommended_actions"]),
      "confidence" => guarded_payload["confidence"],
      "guardrails" => guarded_payload["guardrails"],
      "usage" => guarded_payload["usage"],
      "estimated_cost_usd" => guarded_payload["estimated_cost_usd"]
    }
  rescue StandardError => e
    fallback_payload = apply_guardrails(deterministic_coordination)
    fallback_payload.merge(
      "agent" => self.class.name,
      "company_id" => company.id,
      "generated_at" => Time.current.utc.iso8601,
      "schema" => "ReviewCoordinatorSchema",
      "schema_version" => SCHEMA_VERSION,
      "mode" => "fallback_after_error",
      "error_class" => e.class.name,
      "error_message" => e.message
    )
  end

  private

  attr_reader :company, :evidence_payload, :verification_payload, :description_payload, :critic_payload

  def llm_enabled?
    defined?(RubyLLM) &&
      ENV["OPENAI_API_KEY"].present? &&
      ENV.fetch("REVIEW_COORDINATOR_USE_LLM", ENV.fetch("DESCRIPTION_DRAFTS_USE_LLM", "true")) == "true"
  end

  def llm_coordination
    model = hard_model
    chat = self.class.chat(model: model, provider: :openai, assume_model_exists: unknown_model?(model))
    response = chat.ask(coordination_prompt)
    parsed = parse_json_content(response.content)

    {
      "mode" => "ruby_llm",
      "model" => response.model_id.presence || model,
      "status" => normalized_status(parsed["status"]),
      "reasons" => parsed["reasons"],
      "disagreements" => parsed["disagreements"],
      "recommended_actions" => parsed["recommended_actions"],
      "confidence" => parsed["confidence"],
      "usage" => usage_payload(response),
      "estimated_cost_usd" => estimated_cost(response)
    }
  end

  def deterministic_coordination
    guardrails = guardrail_findings
    status = guardrails.map { |finding| finding["status"] }.max_by { |candidate| STATUS_PRIORITY.fetch(candidate, 0) } || "ready_for_human_review"

    {
      "mode" => "deterministic_fallback",
      "model" => nil,
      "status" => status,
      "reasons" => guardrails.map { |finding| finding["reason"] }.presence || ["No deterministic blockers were found."],
      "disagreements" => deterministic_disagreements,
      "recommended_actions" => recommended_actions_for(status),
      "confidence" => guardrails.any? ? "medium" : "low",
      "usage" => nil,
      "estimated_cost_usd" => nil
    }
  end

  def apply_guardrails(payload)
    guardrails = guardrail_findings
    strongest_guardrail = guardrails.max_by { |finding| STATUS_PRIORITY.fetch(finding["status"], 0) }
    status = normalized_status(payload["status"])
    reasons = Array(payload["reasons"])
    disagreements = Array(payload["disagreements"])
    actions = Array(payload["recommended_actions"])

    if strongest_guardrail && STATUS_PRIORITY.fetch(strongest_guardrail["status"], 0) > STATUS_PRIORITY.fetch(status, 0)
      status = strongest_guardrail["status"]
      reasons << strongest_guardrail["reason"]
      actions |= recommended_actions_for(status)
    end

    payload.merge(
      "status" => status,
      "reasons" => reasons.compact_blank,
      "disagreements" => disagreements.compact_blank,
      "recommended_actions" => actions.compact_blank.presence || recommended_actions_for(status),
      "confidence" => payload["confidence"].presence || "low",
      "guardrails" => guardrails
    )
  end

  def guardrail_findings
    findings = []
    findings << guardrail("do_not_publish", "Verifier flagged this record as reject or hide pending review.") if verification_payload["verdict"] == "reject_or_hide_pending_review"
    findings << guardrail("possible_duplicate", "Duplicate-domain candidate requires human resolution.") if duplicate_signals["duplicate_domain_candidate"]
    findings << guardrail("possible_duplicate", "Duplicate-name candidate requires human resolution.") if duplicate_signals["duplicate_name_candidate"]
    findings << guardrail("needs_description_revision", "Description critic requires revision.") if %w[revise reject].include?(critic_payload["verdict"])
    findings << guardrail("needs_more_evidence", "Evidence agent found missing or thin evidence.") if Array(evidence_payload["evidence_gaps"]).any?
    findings << guardrail("needs_more_evidence", "Verifier flagged missing primary company URL.") if Array(verification_payload["risks"]).include?("Missing primary company URL.")
    findings << guardrail("needs_description_revision", "Verifier flagged unknown or incomplete taxonomy.") if Array(verification_payload["risks"]).include?("Unknown taxonomy.")
    findings << guardrail("needs_description_revision", "Verifier flagged missing tags.") if Array(verification_payload["risks"]).include?("No tags assigned.")
    findings
  end

  def deterministic_disagreements
    disagreements = []
    disagreements << "Draft confidence is high but critic did not pass." if description_payload["confidence"] == "high" && critic_payload["verdict"] != "pass"
    disagreements
  end

  def recommended_actions_for(status)
    case status
    when "ready_for_human_review" then ["Human reviewer can inspect proposed safe fields and decide whether to apply them."]
    when "needs_more_evidence" then ["Add or verify primary website, source URL, LinkedIn, Crunchbase, or other trusted evidence before approving."]
    when "needs_description_revision" then ["Revise the proposed description using critic feedback before approving public text."]
    when "possible_duplicate" then ["Resolve duplicate-domain or duplicate-name candidates before approving field changes."]
    when "do_not_publish" then ["Keep hidden or rejected until a human reviewer confirms relevance and safety."]
    else ["Human reviewer should inspect this packet before taking action."]
    end
  end

  def guardrail(status, reason)
    { "status" => status, "reason" => reason }
  end

  def duplicate_signals
    verification_payload["duplicate_signals"] || {}
  end

  def coordination_prompt
    {
      company: {
        name: company.name,
        description: company.description,
        website: company.main_url,
        category: company.category&.name,
        secondary_category: company.secondary_category&.name,
        revenue_models: company.revenue_model_names,
        target_client: company.target_client&.name,
        target_clients: company.audience_names,
        tags: company.tags.limit(10).pluck(:name),
        ai_capability: AiCapabilityDerivationService.call(company: company)
      },
      evidence: evidence_payload.slice("evidence", "evidence_gaps"),
      evidence_tools: evidence_payload["tool_results"] || {},
      verification: verification_payload.slice("verdict", "quality_score", "risks", "duplicate_signals", "taxonomy_signals", "rationale"),
      description_draft: description_payload.slice("proposed_description", "rationale", "confidence", "warnings"),
      description_critic: critic_payload.slice("verdict", "issues", "rationale", "suggested_revision", "confidence")
    }.to_json
  end

  def parse_json_content(content)
    return content if content.is_a?(Hash)

    JSON.parse(content.to_s)
  rescue JSON::ParserError
    { "status" => "needs_more_evidence", "reasons" => ["Model returned non-JSON content."], "disagreements" => [], "recommended_actions" => ["Human reviewer should inspect raw agent output."], "confidence" => "low" }
  end

  def normalized_status(status)
    STATUSES.include?(status) ? status : "needs_more_evidence"
  end

  def hard_model
    ENV.fetch("RUBYLLM_COORDINATOR_MODEL", ENV.fetch("RUBYLLM_HARD_MODEL", "gpt-5.5"))
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
