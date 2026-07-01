require "timeout"

# Dedicated founding-year lookup for the founded_date backfill. Uses the OpenAI
# Responses API web-search tool so it has its own egress (LinkedIn/Crunchbase/
# registries) and returns cite-able {year, source_url, evidence_text} candidates
# plus the citation URLs it actually saw, so downstream cite-only gating passes for
# genuine sources. This is a year-specific search, unlike the general-purpose
# CompanyProposalResearchService used to draft descriptions.
class CompanyFoundedYearResearchService
  DEFAULT_TIMEOUT_SECONDS = 180

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(company:, search_client: nil)
    @company = company
    @search_client_override = search_client
  end

  def call
    return empty_payload unless web_search_enabled?

    response = resolved_search_client.call(search_prompt)
    parsed = parse_json(response[:content])

    {
      "mode" => "openai_responses_web_search",
      "candidates" => Array(parsed["candidates"]),
      "results" => Array(response[:search_urls]).map { |url| { "url" => url } },
      "generated_at" => Time.current.utc.iso8601
    }
  rescue StandardError => e
    empty_payload.merge("mode" => "openai_responses_web_search_error", "error" => e.class.name, "error_message" => e.message)
  end

  private

  attr_reader :company

  def web_search_enabled?
    @search_client_override.present? || (
      defined?(RubyLLM::ResponsesAPI::BuiltInTools) &&
        ENV["OPENAI_API_KEY"].present? &&
        ENV.fetch("PROPOSAL_WEB_SEARCH_USE_RESPONSES", Rails.env.production? ? "true" : "false") == "true"
    )
  end

  def resolved_search_client
    @search_client_override || default_search_client
  end

  def default_search_client
    lambda do |prompt|
      chat = RubyLLM.chat(model: research_model, provider: :openai_responses, assume_model_exists: true).with_params(tools: [RubyLLM::ResponsesAPI::BuiltInTools.web_search(search_context_size: "medium")])
      response = Timeout.timeout(timeout_seconds) { chat.ask(prompt) }
      output = response.raw&.body&.fetch("output", []) || []
      citations = RubyLLM::ResponsesAPI::BuiltInTools.extract_citations(output.flat_map { |item| Array(item["content"]) })
      search_calls = RubyLLM::ResponsesAPI::BuiltInTools.parse_web_search_results(output)
      citation_urls = Array(citations).filter_map { |citation| citation["url"] }
      call_urls = Array(search_calls).flat_map { |call| Array(call[:results] || call["results"]) }.filter_map { |result| result[:url] || result["url"] }

      { content: response.content.to_s, search_urls: (citation_urls + call_urls).compact.uniq }
    end
  end

  def empty_payload
    { "mode" => "disabled_no_responses_web_search", "candidates" => [], "results" => [] }
  end

  def parse_json(content)
    text = content.to_s.strip
    json_text = text[/\{.*\}/m] || text
    JSON.parse(json_text)
  rescue JSON::ParserError
    { "candidates" => [] }
  end

  def search_prompt
    <<~PROMPT
      Find the founding year of this company using web search.

      Company: #{company.name}
      Website: #{company.main_url}

      Check the "Founded" field on its LinkedIn and Crunchbase profiles and official
      business registries (OpenCorporates, UK Companies House, and national registries).
      Prefer an official registry over a self-reported profile if they disagree.

      Return JSON only:
      {"candidates": [{"year": "YYYY", "source_url": "the exact page URL that states it", "evidence_text": "verbatim snippet that names this company and states the year"}]}

      Include a candidate ONLY if a page explicitly states the founding year for THIS
      company (match the company name and website). List every distinct sourced year you
      find. Never guess or infer. Return an empty candidates array if no page states it.
    PROMPT
  end

  def research_model
    ENV.fetch("RUBYLLM_RESEARCH_MODEL", ENV.fetch("RUBYLLM_HARD_MODEL", "gpt-5.5"))
  end

  def timeout_seconds
    ENV.fetch("FOUNDED_YEAR_SEARCH_TIMEOUT_SECONDS", DEFAULT_TIMEOUT_SECONDS.to_s).to_i
  end
end
