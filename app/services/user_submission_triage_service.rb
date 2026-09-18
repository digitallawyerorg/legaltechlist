require "timeout"

# Is this submission spam, promotional, or worth a look? Triage answers that and nothing
# else. It used to also reject anything whose canonical domain matched a *publicly
# visible* company, which was wrong twice over: it rejected a real submission in the same
# second it arrived, so nobody ever compared the two records, and it missed every other
# shape of duplicate — a rebrand, a new TLD, a hidden draft. Duplicates are resolved by
# CompanyUserSubmissionProcessorService against the shared matcher instead, which routes
# them to a reviewer rather than discarding them.
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
    return verdict("review", 0.8, "marketing_language", "Contains promotional marketing language.") if MARKETING_PATTERNS.count { |pattern| text.match?(pattern) } >= 2

    nil
  end

  def llm_verdict
    return verdict("review", 0.5, "llm_disabled", "LLM triage disabled; queued for human review.") unless llm_enabled?

    response = SubmissionTriageAgent.call(proposal: proposal)
    return verdict("review", 0.5, "llm_error", "LLM triage failed; queued for human review.") if response.blank?

    verdict(response["verdict"], response["confidence"].to_f, "llm", response["reason"])
  rescue StandardError => e
    Rails.logger.debug("[UserSubmissionTriageService] LLM triage failed: #{e.message}")
    verdict("review", 0.5, "llm_error", "LLM triage failed; queued for human review.")
  end

  def llm_enabled?
    defined?(RubyLLM) &&
      ENV["OPENAI_API_KEY"].present? &&
      ENV.fetch("USER_SUBMISSION_TRIAGE_USE_LLM", Rails.env.production? ? "true" : "false") == "true"
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
