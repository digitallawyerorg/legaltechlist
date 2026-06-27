require "timeout"

class CompanyProposalResearchService
  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(proposal:)
    @proposal = proposal
  end

  def call
    return disabled_payload unless responses_web_search_enabled?

    response = Timeout.timeout(llm_timeout_seconds) { responses_chat.ask(research_prompt) }
    output = response.raw&.body&.fetch("output", []) || []
    citations = RubyLLM::ResponsesAPI::BuiltInTools.extract_citations(output.flat_map { |item| Array(item["content"]) })
    search_calls = RubyLLM::ResponsesAPI::BuiltInTools.parse_web_search_results(output)

    {
      "mode" => "openai_responses_web_search",
      "query" => research_query,
      "summary" => response.content.to_s.squish,
      "results" => search_results(citations, search_calls),
      "raw_search_call_count" => search_calls.size,
      "generated_at" => Time.current.utc.iso8601
    }
  rescue StandardError => e
    disabled_payload.merge(
      "mode" => "openai_responses_web_search_error",
      "error" => e.class.name,
      "note" => "Web search failed; enrichment used stored source evidence from the candidate row."
    )
  end

  private

  attr_reader :proposal

  def responses_web_search_enabled?
    defined?(RubyLLM::ResponsesAPI::BuiltInTools) &&
      ENV["OPENAI_API_KEY"].present? &&
      ENV.fetch("PROPOSAL_WEB_SEARCH_USE_RESPONSES", Rails.env.production? ? "true" : "false") == "true"
  end

  def responses_chat
    RubyLLM.chat(model: research_model, provider: :openai_responses, assume_model_exists: true).with_params(tools: [RubyLLM::ResponsesAPI::BuiltInTools.web_search(search_context_size: "medium")])
  end

  def research_model
    ENV.fetch("RUBYLLM_RESEARCH_MODEL", ENV.fetch("RUBYLLM_HARD_MODEL", "gpt-5.5"))
  end

  def llm_timeout_seconds
    ENV.fetch("PROPOSAL_RESEARCH_TIMEOUT_SECONDS", "45").to_i
  end

  def research_prompt
    <<~PROMPT
      Research this legal technology company for a Stanford CodeX TechIndex proposal.

      Company: #{proposal.display_name}
      Website: #{source_payload["website"] || proposal.final_changes["main_url"]}
      Crunchbase: #{source_payload["crunchbase_url"]}
      LinkedIn: #{source_payload["linkedin_url"]}

      Return a concise neutral evidence summary for drafting a directory description.
      Focus on what the company product or service does, who it serves, and legal workflow context.
      Avoid marketing claims, rankings, customer counts, and unsupported superlatives.
    PROMPT
  end

  def disabled_payload
    {
      "mode" => "disabled_no_responses_web_search",
      "query" => research_query,
      "results" => [],
      "note" => "OpenAI Responses API web search is disabled or unavailable; enrichment used stored source evidence from the candidate row."
    }
  end

  def research_query
    [proposal.display_name, source_payload["website"] || proposal.final_changes["main_url"], "legal technology"].compact_blank.join(" ")
  end

  def source_payload
    proposal.source_payload || {}
  end

  def search_results(citations, search_calls)
    citation_results = Array(citations).map { |citation| search_result_payload(citation["title"], citation["url"], citation["text"]) }
    call_results = Array(search_calls).flat_map { |call| Array(call[:results] || call["results"]) }.map { |result| search_result_payload(result[:title] || result["title"], result[:url] || result["url"], result[:snippet] || result["snippet"]) }
    (citation_results + call_results).uniq { |result| result["url"] }.first(8)
  end

  def search_result_payload(title, url, snippet)
    {
      "title" => title.to_s.squish.presence || url,
      "url" => url,
      "snippet" => snippet.to_s.squish.presence
    }.compact
  end
end
