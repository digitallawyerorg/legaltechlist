class CompanyProposalEnrichmentService
  MARKETING_TERMS = DescriptionDraftAgent::MARKETING_TERMS

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(proposal:, admin_user:)
    @proposal = proposal
    @admin_user = admin_user
  end

  def call
    final_changes = proposal.final_changes.merge(enriched_changes)
    proposal.update!(
      status: "ready_for_review",
      final_changes: final_changes,
      proposed_changes: proposal.proposed_changes.merge(enriched_changes),
      agent_details: agent_details(final_changes),
      admin_user: admin_user,
      enriched_at: Time.current
    )

    proposal
  end

  private

  attr_reader :proposal, :admin_user

  def enriched_changes
    {
      "description" => proposed_description,
      "number_of_funding_rounds" => number_of_funding_rounds,
      "employee_count" => source_payload["employee_count"].presence || source_payload["Number of Employees"].presence
    }.compact
  end

  def proposed_description
    clean_description(llm_description.presence || fallback_description)
  end

  def llm_description
    return unless llm_enabled?

    chat = RubyLLM.chat(model: hard_model, provider: :openai, assume_model_exists: true)
    response = chat.ask(description_prompt)
    parsed = JSON.parse(response.content.to_s)
    parsed["proposed_description"]
  rescue StandardError
    nil
  end

  def fallback_description
    industry_text = Array(source_payload["industries"]).first(2).join(" and ").presence
    audience = industry_text ? " in #{industry_text.downcase}" : ""
    "#{display_name} provides or supports legal technology services#{audience}."
  end

  def clean_description(description)
    cleaned = description.to_s.squish
    MARKETING_TERMS.each do |term|
      cleaned = cleaned.gsub(/\b#{Regexp.escape(term)}\b/i, "")
    end
    cleaned = cleaned.gsub(/\b(?:listed|included)\s+in\s+TechIndex\b/i, "")
    cleaned = cleaned.gsub(/\b(?:based on|according to|identified in)\s+(?:available records|directory metadata|stored profiles|source data)\b/i, "")
    cleaned.squish
  end

  def agent_details(final_changes)
    {
      "agent" => self.class.name,
      "mode" => llm_enabled? ? "ruby_llm_or_fallback" : "deterministic_fallback",
      "generated_at" => Time.current.utc.iso8601,
      "source_limits" => [
        "Source descriptions are evidence only and were not copied.",
        "Admin review and editing are required before creating an invisible company draft.",
        "Final publication requires a separate visible toggle."
      ],
      "description_draft" => {
        "proposed_description" => final_changes["description"],
        "confidence" => "low",
        "rationale" => "Drafted conservatively from candidate name and industry/source fields."
      },
      "description_critic" => description_critic(final_changes["description"])
    }
  end

  def description_critic(description)
    issues = []
    issues << "Draft is shorter than expected." if description.to_s.split.size < 12
    issues << "Draft may contain marketing language." if marketing_language?(description)
    issues << "Draft may copy the source description." if copied_source_description?(description)
    issues << "Draft may describe source metadata rather than company facts." if source_meta_language?(description)

    {
      "verdict" => issues.any? ? "revise" : "pass",
      "issues" => issues,
      "rationale" => issues.any? ? "Human revision is recommended before approval." : "No deterministic description issues were found.",
      "suggested_revision" => issues.any? ? fallback_description : "",
      "mode" => "deterministic_fallback"
    }
  end

  def description_prompt
    {
      candidate: source_payload.slice("name", "website", "location", "industries", "operating_status", "company_type"),
      instruction: "Draft a neutral one-sentence legal technology directory description. Do not copy source descriptions. Avoid marketing language and source-meta phrasing."
    }.to_json
  end

  def llm_enabled?
    defined?(RubyLLM) && ENV["OPENAI_API_KEY"].present? && ENV.fetch("PROPOSAL_ENRICHMENT_USE_LLM", ENV.fetch("DESCRIPTION_DRAFTS_USE_LLM", "true")) == "true"
  end

  def hard_model
    ENV.fetch("RUBYLLM_DESCRIPTION_MODEL", ENV.fetch("RUBYLLM_HARD_MODEL", "gpt-5.5"))
  end

  def display_name
    proposal.display_name
  end

  def source_payload
    proposal.source_payload || {}
  end

  def number_of_funding_rounds
    source_payload["number_of_funding_rounds"].presence || source_payload["Number of Funding Rounds"].presence
  end

  def marketing_language?(description)
    text = description.to_s.downcase
    MARKETING_TERMS.any? { |term| text.include?(term) }
  end

  def copied_source_description?(description)
    source_description = source_payload["source_description"].to_s.squish
    source_description.present? && description.to_s.squish.casecmp?(source_description)
  end

  def source_meta_language?(description)
    description.to_s.match?(/\b(available records|directory metadata|stored profiles|source data|current record)\b/i)
  end
end
