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

    blocklist_result = blocklist_verdict(text)
    return blocklist_result if blocklist_result

    return verdict("reject", 0.99, "spam_pattern", "Matched obvious spam pattern.") if SPAM_PATTERNS.any? { |pattern| text.match?(pattern) }
    return verdict("reject", 0.95, "duplicate_domain", "Website domain already listed.") if duplicate_domain_listed?
    return verdict("review", 0.8, "marketing_language", "Contains promotional marketing language.") if MARKETING_PATTERNS.count { |pattern| text.match?(pattern) } >= 2

    nil
  end

  # Checked ahead of the heuristics: a blocklist entry is a curated match on a
  # submission already judged spam by hand, so it rejects on sight rather than
  # leaving a blocker for a curator to notice. The reason names the blocklist so
  # a human can tell these rejections apart from the pattern heuristic.
  def blocklist_verdict(text)
    domain = SubmissionBlocklist.blocked_domain_for(proposal.final_changes["main_url"])
    return verdict("reject", 1.0, "blocklisted_domain", "Submitted domain #{domain} is on the intake spam blocklist.") if domain

    host = SubmissionBlocklist.blocked_link_host_in([text, proposal.final_changes["main_url"]].compact.join(" "))
    return verdict("reject", 1.0, "blocklisted_link", "Submission links to #{host}, which is on the intake spam blocklist.") if host

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
