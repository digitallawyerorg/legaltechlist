require "timeout"

class UserSubmissionTriageService
  SPAM_PATTERNS = [
    /viagra/i, /casino/i, /crypto\s*airdrop/i, /buy\s+followers/i, /seo\s+services/i,
    /click\s+here\s+now/i, /make\s+money\s+fast/i
  ].freeze

  MARKETING_PATTERNS = [
    /\b(best|leading|#1|world[- ]class|revolutionary|game[- ]changing)\b/i,
    /contact us today/i, /limited time offer/i
  ].freeze

  def self.call(proposal:)
    new(proposal: proposal).call
  end

  def initialize(proposal:)
    @proposal = proposal
  end

  def call
    rule_result = rule_verdict
    return rule_result if rule_result

    llm_verdict
  end

  private

  attr_reader :proposal

  def rule_verdict
    text = [proposal.user_message, proposal.final_changes["description"], proposal.final_changes["name"]].compact.join(" ")

    return verdict("reject", 0.99, "spam_pattern", "Matched obvious spam pattern.") if SPAM_PATTERNS.any? { |pattern| text.match?(pattern) }
    return verdict("reject", 0.95, "duplicate_domain", "Website domain already listed.") if duplicate_domain_listed?
    return verdict("review", 0.8, "marketing_language", "Contains promotional marketing language.") if MARKETING_PATTERNS.count { |pattern| text.match?(pattern) } >= 2

    nil
  end

  def duplicate_domain_listed?
    return false unless proposal.user_contribution?

    domain = Company.canonical_domain_for(proposal.final_changes["main_url"])
    return false if domain.blank?

    Company.publicly_visible.where.not(main_url: [nil, ""]).any? { |company| company.canonical_main_domain == domain }
  end

  def llm_verdict
    return verdict("review", 0.5, "llm_disabled", "LLM triage disabled; queued for human review.") unless llm_enabled?

    response = llm_classify
    verdict(response["verdict"], response["confidence"].to_f, "llm", response["reason"])
  rescue StandardError => e
    Rails.logger.debug("[UserSubmissionTriageService] LLM triage failed: #{e.message}")
    verdict("review", 0.5, "llm_error", "LLM triage failed; queued for human review.")
  end

  def llm_classify
    chat = RubyLLM.chat(model: llm_model, provider: :openai, assume_model_exists: true)
    response = Timeout.timeout(llm_timeout_seconds) { chat.ask(llm_prompt) }
    JSON.parse(response.content.to_s)
  end

  def llm_prompt
    <<~PROMPT
      You triage public legal-tech directory submissions. Return JSON only:
      {"verdict":"accept"|"review"|"reject","confidence":0.0-1.0,"reason":"short reason"}

      Proposal type: #{proposal.proposal_type}
      Company name: #{proposal.final_changes['name']}
      Website: #{proposal.final_changes['main_url']}
      Description: #{proposal.final_changes['description']}
      User message: #{proposal.user_message}
      Duplicate domain signals: #{proposal.duplicate_signals['domain_matches'].to_json}
    PROMPT
  end

  def llm_enabled?
    defined?(RubyLLM) &&
      ENV["OPENAI_API_KEY"].present? &&
      ENV.fetch("USER_SUBMISSION_TRIAGE_USE_LLM", Rails.env.production? ? "true" : "false") == "true"
  end

  def llm_model
    ENV.fetch("RUBYLLM_TRIAGE_MODEL", "gpt-4o-mini")
  end

  def llm_timeout_seconds
    ENV.fetch("USER_SUBMISSION_TRIAGE_TIMEOUT_SECONDS", "20").to_i
  end

  def verdict(verdict, confidence, mode, reason)
    {
      "verdict" => verdict.to_s,
      "confidence" => confidence,
      "mode" => mode,
      "reason" => reason
    }
  end
end
