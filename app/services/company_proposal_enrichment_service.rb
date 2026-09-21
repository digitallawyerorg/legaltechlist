require "timeout"
require "uri"

class CompanyProposalEnrichmentService
  # Statuses that mean the proposal is done with the review queue. Enrichment may still
  # run on one (with force), but it must not drag it back into an active queue.
  TERMINAL_STATUSES = %w[approved_to_draft published rejected].freeze

  MARKETING_TERMS = DescriptionDraftAgent::MARKETING_TERMS
  EARLIEST_PLAUSIBLE_FOUNDING_YEAR = 1970

  # Filler phrasing that describes a website/"web presence" instead of an actual
  # product or service. Catches generic enrich fallbacks like "operating x.com as
  # its primary web presence for publishing information and enabling online access".
  GENERIC_WEB_PRESENCE_PATTERN = /
    \b(?:web|online)\s+presence\b |
    \bfor\s+publishing\s+information\b |
    \bonline\s+access\s+to\s+(?:its|their)\s+services\b |
    \bprimary\s+web\b
  /xi

  # Official business registries — the most authoritative founding-year source.
  REGISTRY_HOSTS = %w[
    opencorporates.com
    companieshouse.gov.uk
    sec.gov
    bizfileonline.sos.ca.gov
    handelsregister.de
  ].freeze

  # Self-reported company profiles with a documented "Founded" field.
  PROFILE_HOSTS = %w[
    linkedin.com
    crunchbase.com
  ].freeze

  # Registry/profile hosts we accept for a founding year ONLY when the surrounding
  # evidence text explicitly names the company (guards against same-name entities).
  ENTITY_REGISTRY_HOSTS = (REGISTRY_HOSTS + PROFILE_HOSTS).freeze

  def self.call(**kwargs)
    new(**kwargs).call
  end

  # Normalize a URL to its bare host (lowercased, no leading www.), or nil.
  def self.host_for(url)
    host = URI.parse(url.to_s.strip).host
    host&.downcase&.delete_prefix("www.")
  rescue URI::InvalidURIError
    nil
  end

  # A founding year is accepted ONLY when it is a plausible 4-digit year AND the
  # citing source host is among the evidence we actually gathered (research results
  # or the company's own domains). This prevents writing hallucinated/unsourced years.
  def self.sourced_year(year:, source:, allowed_hosts:)
    normalized = year.to_s.strip
    return nil unless normalized.match?(/\A(?:19|20)\d{2}\z/)
    return nil unless (EARLIEST_PLAUSIBLE_FOUNDING_YEAR..Date.current.year).cover?(normalized.to_i)

    source_host = host_for(source)
    return nil if source_host.blank?
    return nil unless Array(allowed_hosts).include?(source_host)

    normalized
  end

  # True when the citing source is (a) on the company's own canonical domain, or
  # (b) on a known registry/profile host AND the surrounding evidence text explicitly
  # names the company. This blocks year candidates cited from same-name but different
  # entities (e.g. apualegal.com for a company whose canonical domain is apua.ai).
  def self.entity_match?(record, source_url, evidence_text: nil)
    return false if source_url.blank?

    source_domain = Company.canonical_domain_for(source_url)
    return false if source_domain.blank?

    own_domain = own_canonical_domain(record)
    return true if own_domain.present? && domains_related?(source_domain, own_domain)

    return false unless ENTITY_REGISTRY_HOSTS.any? { |host| source_domain == host || source_domain.end_with?(".#{host}") }

    name = display_name_for(record)
    return false if name.blank? || evidence_text.blank?

    evidence_text.to_s.downcase.include?(name.downcase)
  end

  # Returns :registry, :profile, :owned, or :other for a candidate source_url.
  # Used to break ties between multiple entity-matched founding-year candidates.
  def self.source_tier(source_url, company: nil)
    domain = Company.canonical_domain_for(source_url)
    return :other if domain.blank?

    return :registry if REGISTRY_HOSTS.any? { |host| domain == host || domain.end_with?(".#{host}") }
    return :profile if PROFILE_HOSTS.any? { |host| domain == host || domain.end_with?(".#{host}") }

    own = own_canonical_domain(company)
    return :owned if own.present? && domains_related?(domain, own)

    :other
  end

  # Neutralize a drafted description: squish, strip marketing terms and source-meta
  # phrasing. Shared by enrichment and discovery-time drafting so both produce the
  # same house style.
  def self.clean_description(description)
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

  def self.description_issues(description, source_description: nil, full_source_description: nil)
    text = description.to_s
    issues = []
    issues << "Draft is shorter than expected." if text.split.size < 12
    # Word-boundary match so real company names that merely contain a term as a
    # substring (e.g. "BestProfi" containing "best") are not falsely flagged.
    issues << "Draft may contain marketing language." if MARKETING_TERMS.any? { |term| text.match?(/\b#{Regexp.escape(term)}\b/i) }
    issues << "Draft may copy the source description." if [source_description, full_source_description].compact_blank.any? { |source| text.squish.casecmp?(source.to_s.squish) }
    issues << "Draft may describe source metadata rather than company facts." if text.match?(/\b(available records|directory metadata|stored profiles|source data|current record|listed in techindex)\b/i)
    issues << "Draft describes a web presence instead of the company's product or service." if text.match?(GENERIC_WEB_PRESENCE_PATTERN)
    issues << "Draft is too generic for publication." if text.match?(/\bprovides or supports legal technology services\b/i)
    issues
  end

  def self.description_critic_for(description, source_description: nil, full_source_description: nil, suggested_revision: "")
    issues = description_issues(description, source_description: source_description, full_source_description: full_source_description)
    {
      "verdict" => issues.any? ? "revise" : "pass",
      "issues" => issues,
      "rationale" => issues.any? ? "Human revision is recommended before approval." : "No deterministic description issues were found.",
      "suggested_revision" => issues.any? ? suggested_revision.to_s : "",
      "mode" => "deterministic_fallback"
    }
  end

  def self.own_canonical_domain(record)
    return nil if record.nil?
    return record.canonical_main_domain if record.respond_to?(:canonical_main_domain)

    if record.respond_to?(:final_changes)
      main_url = record.final_changes["main_url"].presence || record.try(:source_payload)&.dig("website")
      return Company.canonical_domain_for(main_url)
    end
    nil
  end

  def self.display_name_for(record)
    return record.name if record.respond_to?(:name) && record.name.present?
    record.respond_to?(:display_name) ? record.display_name : nil
  end

  def self.domains_related?(a, b)
    a == b || a.end_with?(".#{b}") || b.end_with?(".#{a}")
  end

  def initialize(proposal:, admin_user:, force: false)
    @proposal = proposal
    @admin_user = admin_user
    @force = ActiveModel::Type::Boolean.new.cast(force)
  end

  # Refused when the record is no longer enrichment's to change. Three approvals were
  # lost to this: a background enrich rewrote the description 31 seconds before the
  # approval landed, so the text that went live was not the text the reviewer read.
  # Once a human has looked at a record, or it has been approved, or its description was
  # deliberately repaired, enrichment stops touching it unless asked explicitly.
  class Locked < StandardError; end

  def refuse_if_locked!
    return if force

    reason = locked_reason
    raise Locked, "Enrichment skipped for proposal #{proposal.id}: #{reason}. Pass force to override." if reason
  end

  # Every description this service replaces is kept, so no wording is ever
  # unrecoverable and a restore is a lookup rather than an archaeology exercise.
  def record_description_history(payload, from:, to:)
    return payload if from.to_s.strip.blank? || from.to_s.strip == to.to_s.strip

    history = Array(proposal.agent_details["description_history"])
    payload.merge("description_history" => history + [{
      "replaced_at" => Time.current.utc.iso8601,
      "replaced_by" => "enrichment",
      "previous" => from
    }])
  end

  def locked_reason
    return "it has already been rejected" if proposal.status == "rejected"
    return "it has already been approved (#{proposal.status})" if proposal.status.in?(%w[approved_to_draft published])
    return "a human reviewed it at #{proposal.reviewed_at.utc.iso8601}" if proposal.reviewed_at.present?
    return "enrichment is turned off for this record" if do_not_enrich?
    return "its description is locked against automated changes" if description_locked?
    # Keyed on the proposal's own state, because a proposal can now be returned before
    # any company exists — the company check below only fires once one does, which is
    # exactly the draft this action was added to avoid creating.
    return "it is waiting on its contributor to answer a reviewer's request" if awaiting_contributor?
    return "the record was returned to its contributor" if proposal.company&.quality_status == CompanyReviewMarkService::RETURNED_STATUS

    nil
  end

  # An outstanding contributor request means the next version of this record is coming
  # from the submitter. Enriching over it now would overwrite the very fields they were
  # asked to fix, and would do it to a record that is not terminal — once they resubmit
  # the request is cleared and enrichment is available again.
  def awaiting_contributor?
    proposal.status == CompanyProposalReturnService::RETURNED_PROPOSAL_STATUS &&
      proposal.agent_details.dig("current_contributor_request", "state") == CompanyProposalReturnService::AWAITING_STATE
  end

  # Set deliberately by a curator or reviewer on a record that keeps being damaged.
  # Durable, and readable through get_proposal and get_company so an agent can see it.
  def do_not_enrich?
    proposal.agent_details["do_not_enrich"] == true ||
      (proposal.company&.quality_review.is_a?(Hash) && proposal.company.quality_review["do_not_enrich"] == true)
  end

  def description_locked?
    proposal.company&.quality_review.is_a?(Hash) && proposal.company.quality_review["description_locked"] == true
  end

  def call
    refuse_if_locked!

    # The web fetch and model calls take 45-90 seconds. Anything decided during that
    # window — a lock set, an approval landing, a human editing — happened after the
    # decision to enrich and must be honoured before the write, not before the fetch.
    load_enrichment_inputs
    previous_description = proposal.final_changes["description"]

    proposal.with_lock do
      proposal.reload
      refuse_if_locked!

      final_changes = proposal.final_changes.merge(enriched_changes).merge(taxonomy_changes)
      agent_payload = agent_details(final_changes)
      agent_payload = record_description_history(agent_payload, from: previous_description, to: final_changes["description"])
      # enriched_at has to be set before the quality report is computed, or the report
      # reads the record as never-researched and blocks on its own enrichment run.
      proposal.assign_attributes(final_changes: final_changes, agent_details: agent_payload, enriched_at: Time.current)
      quality = CompanyProposalQualityService.call(proposal)
      proposal.update!(
        status: enriched_status(quality),
        final_changes: final_changes,
        proposed_changes: proposal.proposed_changes.merge(enriched_changes),
        agent_details: agent_payload.merge("quality" => quality).except("enrichment_error", "enrichment_skipped"),
        admin_user: admin_user,
        enriched_at: Time.current
      )
    end

    proposal.refresh_duplicate_signals!
    proposal
  end

  private

  attr_reader :proposal, :admin_user, :force

  # Gather description + founded year + taxonomy. When the single-call path is enabled
  # (default in production), ONE OpenAI Responses web-search call returns all of it and
  # the taxonomy service just maps names->ids from those suggestions — replacing the
  # former three separate LLM calls (research + taxonomy + description). Otherwise fall
  # back to the legacy path (which itself degrades to deterministic rules without a key).
  def load_enrichment_inputs
    @site_evidence = fetch_site_evidence
    if single_call_enabled?
      @enrichment = ProposalEnrichmentAgent.call(proposal: proposal, site_evidence: @site_evidence)
      @research_payload = @enrichment["web_research"].presence || {}
      @llm_payload = @enrichment.slice("proposed_description", "founded_year", "founded_year_source", "founded_year_evidence_text")
      @taxonomy_suggestion = CompanyProposalTaxonomySuggestionService.call(
        source_payload: source_payload,
        final_changes: proposal.final_changes,
        llm_suggestions: @enrichment["taxonomy_llm_suggestions"]
      )
    else
      @research_payload = CompanyProposalResearchService.call(proposal: proposal)
      @taxonomy_suggestion = CompanyProposalTaxonomySuggestionService.call(source_payload: source_payload, final_changes: proposal.final_changes)
    end
  end

  # Retrieve the candidate's own website and profile pages. Recorded whatever the
  # outcome: a blocked or unreachable site is a finding a reviewer needs, and is not
  # the same thing as never having looked.
  def fetch_site_evidence
    SiteEvidenceFetcherService.call(
      main_url: proposal.final_changes["main_url"].presence || source_payload["website"],
      linkedin_url: proposal.final_changes["linkedin_url"].presence || source_payload["linkedin_url"],
      crunchbase_url: proposal.final_changes["crunchbase_url"].presence || source_payload["crunchbase_url"]
    )
  rescue StandardError => e
    Rails.logger.debug("[CompanyProposalEnrichmentService] site fetch failed for proposal #{proposal&.id}: #{e.class}: #{e.message}")
    { "mode" => "error", "pages" => [], "error" => e.class.name }
  end

  # Where enrichment lands the record. A record nothing could be independently checked
  # against is not ready for a human to sign off on, so it goes back to the queue as
  # needing revision instead of being announced as ready for review.
  # Entity-aware verification of the description against the company's own pages. Reuses
  # the evidence already retrieved, so it costs one model call rather than a second fetch.
  def description_verification(final_changes)
    return @description_verification if defined?(@description_verification)

    @description_verification = if final_changes["description"].to_s.strip.blank?
      nil
    else
      DescriptionVerificationService.call(
        company_name: final_changes["name"],
        company_url: final_changes["main_url"],
        proposed_description: final_changes["description"],
        linkedin_url: final_changes["linkedin_url"],
        crunchbase_url: final_changes["crunchbase_url"],
        site_evidence: @site_evidence
      )
    end
  rescue StandardError => e
    Rails.logger.debug("[CompanyProposalEnrichmentService] verification failed for proposal #{proposal&.id}: #{e.class}: #{e.message}")
    @description_verification = nil
  end

  # Enrichment reports on a proposal; it does not decide where the proposal sits in the
  # workflow. A record that has already been approved into a company draft has left the
  # review queue, and moving it back would put the same piece of work in two places at
  # once — the draft under Company review and the proposal under Review, each looking
  # like it still needs a decision. force overrides the refusal to enrich, not the
  # workflow state the refusal was protecting.
  def enriched_status(quality)
    return proposal.status if proposal.status.in?(TERMINAL_STATUSES)

    quality["verification_state"] == "unverified" ? "needs_revision" : "ready_for_review"
  end

  def single_call_enabled?
    llm_enabled? && ENV.fetch("ENRICHMENT_SINGLE_CALL", "true") == "true"
  end

  def enriched_changes
    @enriched_changes ||= {
      "description" => proposed_description,
      "number_of_funding_rounds" => number_of_funding_rounds,
      "founded_date" => sourced_founded_year
    }.compact
  end

  def taxonomy_changes
    tag_names = Array(taxonomy_suggestion.dig("tags", "names")).compact
    {
      "category_id" => taxonomy_suggestion.dig("category", "id"),
      "secondary_category_id" => taxonomy_suggestion.dig("secondary_category", "id"),
      "business_model_id" => taxonomy_suggestion.dig("revenue_models", "ids")&.first,
      "business_model_ids" => taxonomy_suggestion.dig("revenue_models", "ids"),
      "target_client_id" => taxonomy_suggestion.dig("target_clients", "ids")&.first || taxonomy_suggestion.dig("target_client", "id"),
      "target_client_ids" => taxonomy_suggestion.dig("target_clients", "ids"),
      "all_tags" => tag_names.join(", ").presence
    }.compact_blank
  end

  # Mirror discovery's promote-on-pass rule: use the LLM draft only when it clears
  # the deterministic critic; otherwise fall back to the house-style description
  # (which is written to pass). This keeps quality from dipping when discovery left
  # the description blank and enrichment has to fill it.
  def proposed_description
    @proposed_description ||= begin
      llm = clean_description(llm_payload["proposed_description"])
      fallback = clean_description(fallback_description)
      llm.present? && description_passes_critic?(llm) ? llm : fallback
    end
  end

  def description_passes_critic?(text)
    self.class.description_critic_for(
      text,
      source_description: source_payload["source_description"],
      full_source_description: source_payload["full_source_description"]
    )["verdict"] == "pass"
  end

  # A single LLM call returns description + a strictly-sourced founding year.
  def llm_payload
    @llm_payload ||= fetch_llm_payload
  end

  def fetch_llm_payload
    return {} unless llm_enabled?

    chat = RubyLLM.chat(model: hard_model, provider: :openai, assume_model_exists: true)
    response = Timeout.timeout(llm_timeout_seconds) { chat.ask(description_prompt) }
    payload = parse_json_content(response.content)
    payload.is_a?(Hash) ? payload : {}
  rescue StandardError
    {}
  end

  # Only fill founded_date when it is blank and the model cited a real source we
  # gathered. Records the citing source for provenance/auditing.
  def sourced_founded_year
    return if proposal.final_changes["founded_date"].present?

    candidate_source = llm_payload["founded_year_source"]
    year = self.class.sourced_year(
      year: llm_payload["founded_year"],
      source: candidate_source,
      allowed_hosts: evidence_hosts
    )
    return nil if year.blank?
    return nil unless self.class.entity_match?(proposal, candidate_source, evidence_text: llm_payload["founded_year_evidence_text"])

    @founded_year_source = candidate_source
    year
  end

  def evidence_hosts
    urls = Array(research_payload["results"]).map { |result| result["url"] }
    urls << (source_payload["website"] || proposal.final_changes["main_url"])
    urls << source_payload["crunchbase_url"]
    urls << source_payload["linkedin_url"]
    urls.compact_blank.filter_map { |url| self.class.host_for(url) }.uniq
  end

  def existing_founded_date_source
    (proposal.agent_details || {})["founded_date_source"].presence
  end

  def founded_year_provenance
    return nil if @founded_year_source.blank?

    {
      "source_url" => @founded_year_source,
      "source_tier" => self.class.source_tier(@founded_year_source, company: proposal).to_s,
      "mode" => "web_research_cited",
      "generated_at" => Time.current.utc.iso8601
    }
  end

  def parse_json_content(content)
    return content if content.is_a?(Hash)

    JSON.parse(content.to_s)
  rescue JSON::ParserError
    { "proposed_description" => content.to_s }
  end

  # House-style deterministic fallback used when the LLM is unavailable or its draft
  # fails the critic. Each branch is written to clear the critic (>= 12 words, no
  # marketing/source-meta/web-presence filler) and to read like discovery's crisp,
  # factual one-liners: what it does + who it serves.
  def fallback_description
    text = source_text.downcase

    if text.match?(/\binsurance\b|\bclaims?\b|\bpolic(?:y|ies)\b/)
      "#{display_name} develops legal technology for analyzing insurance policies and claims documentation, serving insurers, legal teams, and claims professionals."
    elsif text.match?(/\bcontract\b|\bnegotiation\b|\bclm\b/)
      "#{display_name} develops legal technology for contract review, drafting, negotiation, and lifecycle management, serving legal, procurement, and commercial teams."
    elsif text.match?(/\blaw firms?\b|\blegal professionals?\b/)
      "#{display_name} develops legal AI software for law firms and legal professionals, supporting research, drafting, and document review workflows."
    elsif text.match?(/\blitigation\b|\bdisputes?\b|\bcase\b/)
      "#{display_name} develops legal technology for litigation and case-management workflows, supporting attorneys and legal teams handling disputes and casework."
    elsif text.match?(/\bcompliance\b|\bregulatory\b|\brisk\b/)
      "#{display_name} develops legal technology for compliance, regulatory, and risk-management workflows, serving in-house legal, compliance, and risk teams."
    else
      "#{display_name} develops legal technology software for legal teams and related professional workflows across the legal services industry."
    end
  end

  def clean_description(description)
    self.class.clean_description(description)
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
      "site_evidence" => @site_evidence,
      "description_verification" => description_verification(final_changes),
      "taxonomy_suggestion" => taxonomy_suggestion,
      "description_draft" => {
        "proposed_description" => final_changes["description"],
        "confidence" => "low",
        "rationale" => description_rationale
      },
      # Reuse any founding-year provenance already recorded (e.g. cited at discovery
      # time) instead of overwriting it with nil when enrichment did not re-search —
      # the year was already found, so we must not lose its source.
      "founded_date_source" => founded_year_provenance || existing_founded_date_source,
      "description_critic" => description_critic(final_changes["description"])
    }
  end

  def description_critic(description)
    self.class.description_critic_for(
      description,
      source_description: source_payload["source_description"],
      full_source_description: source_payload["full_source_description"],
      suggested_revision: fallback_description
    )
  end

  # The description/founding-year drafting instruction, extracted so tooling (e.g.
  # a model bake-off) can exercise the exact production prompt without drift.
  def self.description_instruction
    "Return JSON with keys proposed_description, founded_year, founded_year_source, and founded_year_evidence_text. proposed_description: a neutral, encyclopedic directory description of 2-4 sentences (about 45-90 words) written in the third person, grounded ONLY in the evidence above. Cover, when the evidence supports it: (1) what the company builds and its deployment/business model (e.g. cloud-based platform, marketplace, managed service); (2) its core capabilities and the legal workflows it addresses; (3) who it serves (law firms, corporate/in-house legal, specific practice areas or industries); and (4) notable named products/modules and integrations. Prefer concrete product/function facts over adjectives. Do NOT copy source descriptions verbatim, and avoid marketing language, superlatives, customer counts, source-meta phrasing, generic 'web presence' filler, and the phrase 'provides or supports'. If the evidence is thin, write a shorter factual description rather than padding with speculation. founded_year: the 4-digit founding year ONLY if a source explicitly states it (check the 'Founded' field on the company's LinkedIn/Crunchbase profile and official business registries such as OpenCorporates or national registries; prefer an official registry over a self-reported profile if they disagree), otherwise null — never guess or estimate. founded_year_source: the exact source URL (from the evidence/web_research above) that states the founded_year, otherwise null. founded_year_evidence_text: a short verbatim snippet from that source that names THIS company and states the year (used to confirm the source is about this company and not a same-named one), otherwise null."
  end

  def self.description_prompt_for(candidate:, source_evidence:, web_research: {})
    {
      candidate: candidate,
      source_evidence: source_evidence,
      web_research: web_research,
      instruction: description_instruction
    }.to_json
  end

  def description_prompt
    self.class.description_prompt_for(
      candidate: source_payload.slice("name", "website", "location", "industries", "operating_status", "company_type", "founded_date", "funding_amount_usd", "number_of_funding_rounds", "founders"),
      source_evidence: source_evidence,
      web_research: research_payload
    )
  end

  def llm_enabled?
    defined?(RubyLLM) && ENV["OPENAI_API_KEY"].present? && ENV.fetch("PROPOSAL_ENRICHMENT_USE_LLM", ENV.fetch("DESCRIPTION_DRAFTS_USE_LLM", "true")) == "true"
  end

  def hard_model
    ENV.fetch("RUBYLLM_DESCRIPTION_MODEL", ENV.fetch("RUBYLLM_HARD_MODEL", "gpt-5.5"))
  end

  def llm_timeout_seconds
    ENV.fetch("PROPOSAL_DESCRIPTION_TIMEOUT_SECONDS", "45").to_i
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
end
