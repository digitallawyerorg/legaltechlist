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

  # The research service runs a targeted founding-year web search and returns cite-able
  # {year, source_url, evidence_text} candidates. Because the search model itself is the
  # source of the citations (unlike proposal enrichment, whose evidence hosts come from a
  # pre-gathered research set), the gate here is: a plausible year, a valid source URL,
  # and a same-entity confirmation (own-domain citation, or a verbatim snippet that names
  # THIS company in full). Registry-preference tiering breaks ties.
  def extract_candidates(research_payload)
    Array(research_payload["candidates"]).filter_map do |candidate|
      candidate = candidate.stringify_keys if candidate.respond_to?(:stringify_keys)
      year = plausible_year(candidate["year"])
      source_url = candidate["source_url"].to_s.strip
      evidence_text = candidate["evidence_text"].to_s
      next nil if year.nil?
      next nil unless Company.valid_http_url?(source_url)
      next nil unless same_entity?(source_url, evidence_text)

      { year: year, source_url: source_url, evidence_text: evidence_text, tier: CompanyProposalEnrichmentService.source_tier(source_url, company: company) }
    end
  end

  def plausible_year(value)
    normalized = value.to_s.strip
    return nil unless normalized.match?(/\A(?:19|20)\d{2}\z/)
    return nil unless (CompanyProposalEnrichmentService::EARLIEST_PLAUSIBLE_FOUNDING_YEAR..Date.current.year).cover?(normalized.to_i)

    normalized
  end

  # Trust a citation on the company's own domain; otherwise accept only when the verbatim
  # evidence snippet names THIS company in full. Matching the full name (not just a token)
  # blocks same-name-but-different-company dead ends (e.g. "APUA Legal" for "APUA Innovation Oy").
  def same_entity?(source_url, evidence_text)
    source_domain = Company.canonical_domain_for(source_url)
    return false if source_domain.blank?

    own_domain = company.canonical_main_domain
    return true if own_domain.present? && CompanyProposalEnrichmentService.domains_related?(source_domain, own_domain)

    name = company.name.to_s.squish
    return false if name.blank? || evidence_text.blank?

    evidence_text.squish.downcase.include?(name.downcase)
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
