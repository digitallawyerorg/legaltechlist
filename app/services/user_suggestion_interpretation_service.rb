require "timeout"

class UserSuggestionInterpretationService
  FIELD_KEYS = CompanyProposal::EDITABLE_COMPANY_FIELDS

  def self.call(proposal:)
    new(proposal: proposal).call
  end

  def initialize(proposal:)
    @proposal = proposal
  end

  def call
    return deterministic_delta if deterministic_delta.any?
    return llm_delta if llm_enabled?

    {}
  end

  private

  attr_reader :proposal

  def deterministic_delta
    delta = {}
    message = proposal.user_message.to_s
    issue_type = proposal.issue_type.to_s

    if issue_type == "broken_link" && proposal.source_payload["source_url"].present?
      delta["main_url"] = proposal.source_payload["source_url"] if message.match?(/website|homepage|main url/i)
      delta["linkedin_url"] = proposal.source_payload["source_url"] if message.match?(/linkedin/i)
      delta["crunchbase_url"] = proposal.source_payload["source_url"] if message.match?(/crunchbase/i)
    end

    founded_match = message.match(/\b(19|20)\d{2}\b/)
    delta["founded_date"] = founded_match[0] if issue_type.in?(%w[incorrect_details]) && founded_match

    if message.match?(/\bdescription\b/i)
      description_match = message.match(/\b(?:update|change|set|correct)\s+(?:the\s+)?description\s+to\s+(.+)/im) ||
        message.match(/\bdescription\s+should\s+be\s+(.+)/im)
      proposed_description = description_match&.[](1).to_s.strip
      delta["description"] = proposed_description if proposed_description.present?
    end

    delta.slice(*FIELD_KEYS)
  end

  def llm_delta
    chat = RubyLLM.chat(model: llm_model, provider: :openai, assume_model_exists: true)
    response = Timeout.timeout(llm_timeout_seconds) { chat.ask(llm_prompt) }
    parsed = JSON.parse(response.content.to_s)
    changes = parsed["proposed_changes"].is_a?(Hash) ? parsed["proposed_changes"] : {}
    changes.slice(*FIELD_KEYS)
  rescue StandardError => e
    Rails.logger.debug("[UserSuggestionInterpretationService] LLM interpretation failed: #{e.message}")
    {}
  end

  def llm_prompt
    current = proposal.proposed_changes.slice(*FIELD_KEYS)
    <<~PROMPT
      Parse a user suggestion for a legal-tech company directory into field updates.
      Return JSON only: {"proposed_changes": {field: value}}
      Allowed fields: #{FIELD_KEYS.join(', ')}
      Issue type: #{proposal.issue_type}
      User message: #{proposal.user_message}
      Supporting URL: #{proposal.source_payload['source_url']}
      Current values: #{current.to_json}
      Only include fields that should change based on the message.
    PROMPT
  end

  def llm_enabled?
    defined?(RubyLLM) &&
      ENV["OPENAI_API_KEY"].present? &&
      ENV.fetch("USER_SUGGESTION_INTERPRET_USE_LLM", Rails.env.production? ? "true" : "false") == "true"
  end

  def llm_model
    ENV.fetch("RUBYLLM_TRIAGE_MODEL", "gpt-4o-mini")
  end

  def llm_timeout_seconds
    ENV.fetch("USER_SUGGESTION_INTERPRET_TIMEOUT_SECONDS", "20").to_i
  end
end
