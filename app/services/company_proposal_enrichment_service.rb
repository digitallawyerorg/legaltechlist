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
    @research_payload = CompanyProposalResearchService.call(proposal: proposal)
    @taxonomy_suggestion = CompanyProposalTaxonomySuggestionService.call(source_payload: source_payload, final_changes: proposal.final_changes)
    final_changes = proposal.final_changes.merge(enriched_changes).merge(taxonomy_changes)
    agent_payload = agent_details(final_changes)
    proposal.update!(
      status: "ready_for_review",
      final_changes: final_changes,
      proposed_changes: proposal.proposed_changes.merge(enriched_changes),
      agent_details: agent_payload.merge("quality" => CompanyProposalQualityService.call(proposal.tap { |record| record.final_changes = final_changes; record.agent_details = agent_payload })),
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

  def taxonomy_changes
    {
      "category_id" => taxonomy_suggestion.dig("category", "id"),
      "business_model_id" => taxonomy_suggestion.dig("business_model", "id"),
      "target_client_id" => taxonomy_suggestion.dig("target_client", "id")
    }.compact_blank
  end

  def proposed_description
    clean_description(llm_description.presence || fallback_description)
  end

  def llm_description
    return unless llm_enabled?

    chat = RubyLLM.chat(model: hard_model, provider: :openai, assume_model_exists: true)
    response = chat.ask(description_prompt)
    parsed = parse_json_content(response.content)
    parsed["proposed_description"]
  rescue StandardError
    nil
  end

  def parse_json_content(content)
    return content if content.is_a?(Hash)

    JSON.parse(content.to_s)
  rescue JSON::ParserError
    { "proposed_description" => content.to_s }
  end

  def fallback_description
    text = source_text.downcase

    if text.match?(/\binsurance\b|\bclaims?\b|\bpolic(?:y|ies)\b/)
      "#{display_name} develops legal technology for analyzing insurance policies and claims documentation."
    elsif text.match?(/\bcontract\b|\bnegotiation\b|\bclm\b/)
      "#{display_name} develops legal technology for contract review, drafting, negotiation, or lifecycle management."
    elsif text.match?(/\blaw firms?\b|\blegal professionals?\b/)
      "#{display_name} develops legal AI software for law firms and legal professionals."
    elsif text.match?(/\blitigation\b|\bdisputes?\b|\bcase\b/)
      "#{display_name} develops legal technology for litigation and case-management workflows."
    elsif text.match?(/\bcompliance\b|\bregulatory\b|\brisk\b/)
      "#{display_name} develops legal technology for compliance, regulatory, or risk-management workflows."
    else
      "#{display_name} develops legal technology software for legal teams and related professional workflows."
    end
  end

  def clean_description(description)
    cleaned = description.to_s.squish
    MARKETING_TERMS.each do |term|
      cleaned = cleaned.gsub(/\b#{Regexp.escape(term)}\b/i, "")
    end
    cleaned = cleaned.gsub(/\bprovides or supports\b/i, "develops")
    cleaned = cleaned.gsub(/\b(?:listed|included)\s+in\s+TechIndex\b/i, "")
    cleaned = cleaned.gsub(/\b(?:based on|according to|identified in)\s+(?:available records|directory metadata|stored profiles|source data)\b/i, "")
    cleaned = cleaned.gsub(/\bai\b/i, "AI")
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
      "web_research" => research_payload,
      "taxonomy_suggestion" => taxonomy_suggestion,
      "description_draft" => {
        "proposed_description" => final_changes["description"],
        "confidence" => "low",
        "rationale" => description_rationale
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
    issues << "Draft is too generic for publication." if generic_description?(description)

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
      candidate: source_payload.slice("name", "website", "location", "industries", "operating_status", "company_type", "founded_date", "funding_amount_usd", "number_of_funding_rounds", "employee_count", "founders"),
      source_evidence: source_evidence,
      web_research: research_payload,
      instruction: "Return JSON with key proposed_description. Draft one neutral, academic directory sentence of 18-32 words. Use concrete product/function language grounded only in evidence. Do not copy source descriptions. Avoid marketing language, source-meta phrasing, customer counts, unverifiable superlatives, and the phrase 'provides or supports'."
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

  def source_evidence
    {
      "short_description" => source_payload["source_description"],
      "full_description" => source_payload["full_source_description"],
      "industries" => Array(source_payload["industries"]),
      "website" => source_payload["website"],
      "crunchbase_url" => source_payload["crunchbase_url"],
      "linkedin_url" => source_payload["linkedin_url"]
    }.compact
  end

  def research_payload
    @research_payload ||= CompanyProposalResearchService.call(proposal: proposal)
  end

  def taxonomy_suggestion
    @taxonomy_suggestion ||= CompanyProposalTaxonomySuggestionService.call(source_payload: source_payload, final_changes: proposal.final_changes)
  end

  def source_text
    [
      source_payload["source_description"],
      source_payload["full_source_description"],
      Array(source_payload["industries"]).join(" ")
    ].compact.join(" ")
  end

  def description_rationale
    if Array(research_payload["results"]).any? || research_payload["summary"].present?
      "Drafted from candidate source evidence and OpenAI Responses API web-search research, then filtered for neutral academic tone."
    else
      "Drafted from candidate source evidence because web search was unavailable."
    end
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

  def generic_description?(description)
    description.to_s.match?(/\bprovides or supports legal technology services\b/i)
  end
end
