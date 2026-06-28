require "timeout"

class CompanyDiscoverySearchService
  DISCOVERY_TYPES = %w[category competitors year country funding_year].freeze

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(discovery_type:, context:, exclusion_list:, limit:, search_client: nil)
    @discovery_type = discovery_type.to_s
    @context = context
    @exclusion_list = exclusion_list
    @limit = limit.to_i
    @search_client_override = search_client
  end

  def call
    return disabled_payload unless web_search_enabled?

    response = resolved_search_client.call(search_prompt)
    parsed = parse_companies_json(response[:content])
    search_urls = Array(response[:search_urls])
    companies = Array(parsed["companies"]).first(limit).filter_map { |company| build_company_payload(company, search_urls) }

    {
      "mode" => "openai_responses_web_search",
      "discovery_type" => discovery_type,
      "query" => search_query,
      "companies" => companies,
      "raw_search_call_count" => response[:raw_search_call_count],
      "generated_at" => Time.current.utc.iso8601
    }
  rescue StandardError => e
    disabled_payload.merge(
      "mode" => "openai_responses_web_search_error",
      "error" => e.class.name,
      "error_message" => e.message
    )
  end

  private

  attr_reader :discovery_type, :context, :exclusion_list, :limit

  def web_search_enabled?
    @search_client_override.present? || (
      defined?(RubyLLM::ResponsesAPI::BuiltInTools) &&
        ENV["OPENAI_API_KEY"].present? &&
        ENV.fetch("DISCOVERY_USE_WEB_SEARCH", "true") == "true"
    )
  end

  def resolved_search_client
    @resolved_search_client ||= @search_client_override || default_search_client
  end

  def default_search_client
    return nil unless web_search_enabled?

    lambda do |prompt|
      chat = RubyLLM.chat(model: research_model, provider: :openai_responses, assume_model_exists: true).with_params(tools: [RubyLLM::ResponsesAPI::BuiltInTools.web_search(search_context_size: "medium")])
      response = Timeout.timeout(llm_timeout_seconds) { chat.ask(prompt) }
      output = response.raw&.body&.fetch("output", []) || []
      citations = RubyLLM::ResponsesAPI::BuiltInTools.extract_citations(output.flat_map { |item| Array(item["content"]) })
      search_calls = RubyLLM::ResponsesAPI::BuiltInTools.parse_web_search_results(output)
      search_urls = extract_search_urls(citations, search_calls)

      {
        content: response.content.to_s,
        search_urls: search_urls,
        raw_search_call_count: search_calls.size
      }
    end
  end

  def disabled_payload
    {
      "mode" => "disabled_no_responses_web_search",
      "discovery_type" => discovery_type,
      "query" => search_query,
      "companies" => [],
      "note" => "OpenAI Responses API web search is disabled or unavailable."
    }
  end

  def research_model
    ENV.fetch("RUBYLLM_DISCOVERY_MODEL", ENV.fetch("RUBYLLM_RESEARCH_MODEL", ENV.fetch("RUBYLLM_HARD_MODEL", "gpt-5.5")))
  end

  def llm_timeout_seconds
    ENV.fetch("DISCOVERY_TIMEOUT_SECONDS", ENV.fetch("PROPOSAL_RESEARCH_TIMEOUT_SECONDS", "90")).to_i
  end

  def search_query
    case discovery_type
    when "category"
      "legal technology companies in #{context.fetch(:category)} category"
    when "competitors"
      "competitors and alternatives to #{context.fetch(:company_name)} legal technology"
    when "year"
      "legal technology companies founded in #{context.fetch(:year)}"
    when "country"
      "legal technology companies headquartered in #{context.fetch(:country)}"
    when "funding_year"
      "legal technology companies that raised funding in #{context.fetch(:funding_year)}"
    else
      "legal technology companies"
    end
  end

  def search_prompt
    <<~PROMPT
      You are discovering legal-technology companies for the Stanford CodeX TechIndex directory.

      Discovery task: #{search_query}
      #{discovery_task_guidance}
      Return up to #{limit} distinct companies not already listed in TechIndex.

      Exclude these existing index entries (name or domain):
      #{formatted_exclusion_list}

      Use web search to find real, market-facing legal technology vendors.
      Only include companies whose official website appears in search results.
      Do not invent URLs, funding figures, or company details.

      Return JSON only with this shape:
      #{json_output_schema}
    PROMPT
  end

  def discovery_task_guidance
    case discovery_type
    when "year"
      "Focus on legal-tech vendors founded in #{context.fetch(:year)}. Prefer companies whose founding year is documented in search results."
    when "country"
      "Focus on legal-tech vendors headquartered in #{context.fetch(:country)}. Prefer companies with a clear HQ location in that country."
    when "funding_year"
      "Focus on legal-tech vendors that raised venture or growth funding in #{context.fetch(:funding_year)}. Include only companies where the funding round year is documented in search results."
    else
      ""
    end
  end

  def json_output_schema
    base_fields = <<~FIELDS.strip
      "name": "Company Name",
            "website": "https://example.com",
            "location": "City, Country",
            "founded_date": "2018",
            "description": "One neutral sentence on what the company does for legal workflows.",
            "why_discovered": "Short reason this company matches the discovery task."
    FIELDS

    funding_fields = <<~FIELDS.strip
      "name": "Company Name",
            "website": "https://example.com",
            "location": "City, Country",
            "founded_date": "2018",
            "description": "One neutral sentence on what the company does for legal workflows.",
            "why_discovered": "Short reason this company matches the discovery task.",
            "funding_round_year": "2024",
            "funding_round_type": "Series A",
            "funding_amount_hint": "Optional amount or range if documented in search results."
    FIELDS

    fields = discovery_type == "funding_year" ? funding_fields : base_fields

    <<~SCHEMA.strip
      {
        "companies": [
          {
            #{fields}
          }
        ]
      }
    SCHEMA
  end

  def formatted_exclusion_list
    names = Array(exclusion_list["names"]).first(200)
    domains = Array(exclusion_list["domains"]).first(200)
    lines = names.map { |name| "- #{name}" } + domains.map { |domain| "- #{domain}" }
    lines.presence&.join("\n") || "- none provided"
  end

  def parse_companies_json(content)
    text = content.to_s.strip
    json_text = text[/\{.*\}/m] || text
    JSON.parse(json_text)
  rescue JSON::ParserError
    { "companies" => [] }
  end

  def build_company_payload(company, search_urls)
    name = company["name"].to_s.strip
    website = clean_url(company["website"])
    return if name.blank? || website.blank?

    payload = {
      "name" => name,
      "website" => website,
      "location" => company["location"].to_s.strip.presence,
      "founded_date" => company["founded_date"].to_s.strip.presence,
      "description" => company["description"].to_s.squish.presence,
      "why_discovered" => company["why_discovered"].to_s.squish.presence,
      "discovery_type" => discovery_type,
      "discovery_query" => search_query,
      "website_verified" => verified_website?(website, search_urls)
    }
    payload.merge!(funding_hint_payload(company)) if discovery_type == "funding_year"
    payload.compact
  end

  def extract_search_urls(citations, search_calls)
    citation_urls = Array(citations).filter_map { |citation| citation["url"] }
    call_urls = Array(search_calls).flat_map { |call| Array(call[:results] || call["results"]) }.filter_map { |result| result[:url] || result["url"] }
    (citation_urls + call_urls).compact.uniq
  end

  def verified_website?(website, search_urls)
    domain = Company.canonical_domain_for(website)
    return false if domain.blank?

    search_urls.any? do |url|
      cited_domain = Company.canonical_domain_for(url)
      next false if cited_domain.blank?

      cited_domain == domain || cited_domain.end_with?(".#{domain}") || domain.end_with?(".#{cited_domain}")
    end
  end

  def funding_hint_payload(company)
    {
      "funding_round_year" => company["funding_round_year"].to_s.strip.presence,
      "funding_round_type" => company["funding_round_type"].to_s.strip.presence,
      "funding_amount_hint" => company["funding_amount_hint"].to_s.squish.presence
    }.compact
  end

  def clean_url(url)
    value = url.to_s.strip
    return nil if value.blank?

    value.match?(%r{\Ahttps?://}i) ? value : "https://#{value}"
  end
end
