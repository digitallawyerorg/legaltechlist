require "timeout"

# Backfills a blank founded_date on a published company from web-cited sources.
# Reuses the exact cite-only guard (CompanyProposalEnrichmentService.sourced_year),
# the same-entity guard (entity_match?), and the registry-preference tiering
# (source_tier). Writes only through Company#founded_date_from_source! and records
# provenance so any backfilled year is auditable.
class CompanyFoundedDateBackfillService
  TIER_RANK = { registry: 0, profile: 1, owned: 2, other: 3 }.freeze

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(company:, admin_user: nil)
    @company = company
    @admin_user = admin_user
  end

  # Returns a hash: { "result" =>, "company_id" =>, "year" =>, "source_url" =>, "source_tier" =>, "reason" => }
  def call
    return { "result" => "skipped_present", "company_id" => company.id } if company.founded_date.present?

    research = fetch_research
    chosen = choose_candidate(extract_candidates(research))
    return { "result" => "skipped_no_source", "company_id" => company.id, "reason" => "no cited candidate year in gathered evidence" } if chosen.nil?

    company.founded_date_from_source!(year: chosen[:year], source_url: chosen[:source_url])
    record_provenance!(chosen)
    audit!(chosen)

    { "result" => "filled", "company_id" => company.id, "year" => chosen[:year], "source_url" => chosen[:source_url], "source_tier" => chosen[:tier].to_s }
  rescue ArgumentError => e
    { "result" => "skipped_no_year", "company_id" => company.id, "reason" => e.message }
  rescue StandardError => e
    Rails.logger.debug("[CompanyFoundedDateBackfillService] company_id=#{company.id} #{e.class}: #{e.message}")
    { "result" => "error", "company_id" => company.id, "reason" => "#{e.class}: #{e.message}" }
  end

  private

  attr_reader :company, :admin_user

  def fetch_research
    CompanyProposalResearchService.call(company: company)
  end

  # Prefer a pre-extracted candidates list on the research payload (used in tests);
  # otherwise run a focused LLM extraction over the gathered evidence. Every candidate
  # is filtered through the SAME cite-only + same-entity guards used by enrichment.
  def extract_candidates(research_payload)
    raw = research_payload["candidates"].presence || llm_year_candidates(research_payload)
    allowed_hosts = evidence_hosts(research_payload)

    Array(raw).filter_map do |candidate|
      candidate = candidate.stringify_keys if candidate.respond_to?(:stringify_keys)
      source_url = candidate["source_url"]
      year = CompanyProposalEnrichmentService.sourced_year(year: candidate["year"], source: source_url, allowed_hosts: allowed_hosts)
      next nil if year.nil?
      next nil unless CompanyProposalEnrichmentService.entity_match?(company, source_url, evidence_text: candidate["evidence_text"])

      { year: year, source_url: source_url, evidence_text: candidate["evidence_text"], tier: CompanyProposalEnrichmentService.source_tier(source_url, company: company) }
    end
  end

  def evidence_hosts(research_payload)
    urls = Array(research_payload["results"]).map { |result| result["url"] }
    urls << company.main_url
    urls.compact_blank.filter_map { |url| CompanyProposalEnrichmentService.host_for(url) }.uniq
  end

  # Registry > profile > owned > other, then earlier collection order.
  def choose_candidate(candidates)
    candidates.each_with_index.min_by { |candidate, index| [TIER_RANK.fetch(candidate[:tier], 99), index] }&.first
  end

  def llm_year_candidates(research_payload)
    return [] unless llm_enabled?

    chat = RubyLLM.chat(model: research_model, provider: :openai, assume_model_exists: true)
    response = Timeout.timeout(llm_timeout_seconds) { chat.ask(extraction_prompt(research_payload)) }
    parsed = JSON.parse(response.content.to_s)
    Array(parsed["candidates"])
  rescue StandardError => e
    Rails.logger.debug("[CompanyFoundedDateBackfillService] extraction failed company_id=#{company.id}: #{e.message}")
    []
  end

  def extraction_prompt(research_payload)
    {
      company: { name: company.name, website: company.main_url },
      web_research: research_payload,
      instruction: "From the web_research evidence ONLY, extract founding-year claims for THIS company. Return JSON {\"candidates\": [{\"year\": \"YYYY\", \"source_url\": \"exact evidence URL\", \"evidence_text\": \"verbatim snippet that names this company and states the year\"}]}. Include a candidate ONLY when a source explicitly states the founding year and its source_url is one of the evidence URLs. Prefer official registries (OpenCorporates, national registries) and profile 'Founded' fields (LinkedIn/Crunchbase). Never guess or infer. Return an empty candidates array if no source states a year."
    }.to_json
  end

  def llm_enabled?
    defined?(RubyLLM) && ENV["OPENAI_API_KEY"].present? && ENV.fetch("PROPOSAL_ENRICHMENT_USE_LLM", ENV.fetch("DESCRIPTION_DRAFTS_USE_LLM", "true")) == "true"
  end

  def research_model
    ENV.fetch("RUBYLLM_RESEARCH_MODEL", ENV.fetch("RUBYLLM_HARD_MODEL", "gpt-5.5"))
  end

  def llm_timeout_seconds
    ENV.fetch("PROPOSAL_RESEARCH_TIMEOUT_SECONDS", "45").to_i
  end

  def record_provenance!(chosen)
    return unless company.respond_to?(:founded_year_provenance=)

    company.update_columns(founded_year_provenance: {
      "source_url" => chosen[:source_url],
      "source_tier" => chosen[:tier].to_s,
      "mode" => "server_backfill",
      "generated_at" => Time.current.utc.iso8601
    })
  end

  def audit!(chosen)
    PipelineRun.create!(
      name: "Backfill founded_date",
      run_type: "founded_date_backfill",
      status: "succeeded",
      agent_name: "CompanyFoundedDateBackfillService",
      records_processed: 1,
      started_at: Time.current,
      finished_at: Time.current,
      details: { "company_id" => company.id, "year" => chosen[:year], "source_url" => chosen[:source_url], "source_tier" => chosen[:tier].to_s }
    )
  rescue StandardError => e
    Rails.logger.debug("[CompanyFoundedDateBackfillService] audit failed: #{e.message}")
    nil
  end
end
