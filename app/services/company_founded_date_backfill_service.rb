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
    CompanyFoundedYearResearchService.call(company: company)
  end

  # The research service returns cite-able {year, source_url, evidence_text} candidates
  # from a targeted founding-year web search. Every candidate is filtered through the
  # SAME cite-only + same-entity guards used by enrichment.
  def extract_candidates(research_payload)
    allowed_hosts = evidence_hosts(research_payload)

    Array(research_payload["candidates"]).filter_map do |candidate|
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
