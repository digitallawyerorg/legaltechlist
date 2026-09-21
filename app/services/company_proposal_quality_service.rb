class CompanyProposalQualityService
  REQUIRED_FIELDS = %w[name main_url location founded_date description category_id business_model_id target_client_id].freeze
  # Fields whose absence actually blocks publication. founded_date is intentionally
  # excluded: it is often unsourceable for small/international companies, so a missing
  # founding year is a non-blocking warning (flag for backfill) rather than a blocker.
  PUBLISH_BLOCKING_FIELDS = %w[name main_url location description category_id business_model_id target_client_id].freeze

  def self.call(proposal)
    new(proposal).call
  end

  def initialize(proposal)
    @proposal = proposal
  end

  def call
    {
      "score" => score,
      "publish_ready" => blockers.empty?,
      "missing_required_fields" => missing_required_fields,
      "missing_publish_blocking_fields" => missing_publish_blocking_fields,
      "blockers" => blockers,
      "description_critic" => description_critic,
      "warnings" => warnings,
      "usable_web_evidence_count" => usable_web_results.size,
      "usable_source_evidence_count" => usable_source_evidence_count,
      "fetched_page_count" => fetched_pages.size,
      "independent_evidence_count" => independent_evidence_count,
      "verification_state" => verification_state,
      "description_verification" => description_verification,
      "description_verified" => description_verified?,
      "duplicate_signals" => duplicate.signals,
      "checked_at" => Time.current.utc.iso8601
    }
  end

  private

  attr_reader :proposal

  def changes
    @changes ||= proposal.editable_changes
  end

  def missing_required_fields
    missing = REQUIRED_FIELDS.select { |field| scalar_field_blank?(field) }
    missing << "business_model_id" unless proposal.revenue_models_present?(changes)
    missing << "target_client_id" unless proposal.target_clients_present?(changes)
    missing.uniq
  end

  def missing_publish_blocking_fields
    missing_required_fields & PUBLISH_BLOCKING_FIELDS
  end

  def scalar_field_blank?(field)
    return false if field.in?(%w[business_model_id target_client_id])

    changes[field].blank?
  end

  def blockers
    @blockers ||= begin
      values = []
      values << duplicate.recommended_action if duplicate.blocking?
      values << "Complete required fields before publishing: #{missing_publish_blocking_fields.map(&:humanize).to_sentence}." if missing_publish_blocking_fields.any?
      values << "Review low-confidence taxonomy before publishing." if low_confidence_taxonomy?
      values << description_blocker if description_blocker
      values << "Possible spam or malformed public submission — requires human review before publishing." if spam_suspected?
      values << "This record has not been researched yet. Run Enrich before publishing." if not_researched?
      values << unverified_blocker if unverified_blocker
      values << verification_blocker if verification_blocker
      values
    end
  end

  # The report reads the same gate every write path does, so a reviewer is never told a
  # record is publish-ready that the gate would stop. It is a read: no fresh resolution
  # (a list view has usually just resolved these rows) and no evidence written, since
  # rendering a report is not a disposition. The wording names the matched record rather
  # than announcing that a signal exists, so a reviewer can act without opening a second
  # tab to work out what matched.
  def duplicate
    @duplicate ||= DuplicateGate.check(proposal, refresh: false, record_evidence: false)
  end

  # A proposal that was never enriched has had no research applied to it at all, yet
  # scored as publish-ready purely because its fields were populated at intake.
  # Enrichment is one way to research a record; a curator reading the pages themselves
  # is another. Twenty records were held by this gate whose only exit was the operation
  # that overwrites the description, so curator-recorded citations satisfy it too.
  def not_researched?
    proposal.enriched_at.blank? && curator_recorded_evidence.empty?
  end

  def curator_recorded_evidence
    @curator_recorded_evidence ||= Array(proposal.agent_details.dig("web_research", "results"))
                                   .select { |result| result["recorded_by"] == "curator" }
  end

  # Self-reported links (the submitter's own website and profile URLs) establish that a
  # company claims to exist, not that anything was checked. Publication requires at
  # least one independently retrieved source: a page enrichment actually fetched, or a
  # search citation. This is what "no evidence attached" meant in practice.
  def unverified_blocker
    return nil if independent_evidence_count.positive?

    if fetch_blocked?
      "The company's own site could not be retrieved (#{fetch_block_reasons.to_sentence}), so nothing here is independently verified. Confirm the record by hand before publishing."
    else
      "No independently retrieved evidence supports this record — only self-reported links. Run Enrich to fetch the company's site before publishing."
    end
  end

  # The entity-aware verification verdict. MANUAL_REVIEW and REJECT are held decisions,
  # not warnings: in both cases the reviewer has to look, so publication waits.
  def description_verification
    @description_verification ||= proposal.agent_details["description_verification"]
  end

  # True only when verification actually looked and approved. A skipped check is not a
  # pass: the crash that used to block publishing was, by accident, the only thing
  # keeping unreviewed machine text off the public index, so removing the block has to
  # come with an explicit signal that autonomous publication can gate on.
  def description_verified?
    description_verification.present? && description_verification["decision"] == DescriptionVerificationService::APPROVE
  end

  def verification_blocker
    return nil unless DescriptionVerificationService.blocking?(description_verification)

    reason = description_verification["accuracy_assessment"].presence
    case description_verification["decision"]
    when DescriptionVerificationService::REJECT
      "Verification rejected this record for the index#{" — #{reason}" if reason}"
    else
      "Verification could not confirm this description#{" — #{reason}" if reason} Check it by hand before publishing."
    end
  end

  # Enforce the description critic verdict consistently across every path
  # (discovery, enrichment, and manual edits). The verdict is computed live on the
  # current draft — never trusting a possibly-stale stored verdict — so a "revise"
  # description can never be published regardless of how it was authored. Blank
  # descriptions are handled by missing_publish_blocking_fields, so we skip them
  # here to avoid double-reporting.
  def description_blocker
    return nil if changes["description"].blank?
    return nil if description_critic_verdict["verdict"] == "pass"

    issues = Array(description_critic_verdict["issues"]).map(&:to_s).map(&:downcase).to_sentence.presence
    issues ? "Revise the description before publishing (#{issues})." : "Revise the description before publishing."
  end

  def description_critic_verdict
    @description_critic_verdict ||= CompanyProposalEnrichmentService.description_critic_for(
      changes["description"],
      source_description: proposal.source_payload["source_description"],
      full_source_description: proposal.source_payload["full_source_description"]
    )
  end

  # The critic verdict exposed on the report so readers (get_proposal,
  # list_review_queue) see the SAME determination the publish gate acts on — never
  # a stale stored verdict. Nil when there is no description yet (a missing
  # description is reported via missing_publish_blocking_fields instead).
  def description_critic
    return nil if changes["description"].blank?

    description_critic_verdict
  end

  # Public submissions are the main spam vector (recruitment/advance-fee scams,
  # solicitations, junk stuffed into date/url fields). Discovery candidates are
  # generated internally, so this heuristic is intentionally scoped to
  # externally-submitted proposals to avoid false positives on the wider dataset.
  SOLICITATION_PATTERN = /
    mailto: |
    \bunsubscribe\b |
    \bsalary\b |
    \bwire\s+transfer\b |
    \bwestern\s+union\b |
    money\s*(mule|agent|transfer) |
    \brecruit(?:ing|ment)?\b |
    \$\s?\d{3,}
  /xi

  def spam_suspected?
    return false unless proposal.externally_submitted?

    solicitation_text? || malformed_founded_date? || malformed_main_url?
  end

  def solicitation_text?
    blob = [changes["description"], changes["founders"], proposal.user_message].compact_blank.join(" ")
    blob.match?(SOLICITATION_PATTERN)
  end

  def malformed_founded_date?
    value = changes["founded_date"].to_s.strip
    return false if value.blank?

    !value.match?(/\b(1[89]\d{2}|20\d{2})\b/) && (Date._parse(value)[:year].nil?)
  end

  def malformed_main_url?
    value = changes["main_url"].to_s.strip
    return false if value.blank?

    uri = URI.parse(value)
    !(uri.is_a?(URI::HTTP) && uri.host.present?)
  rescue URI::InvalidURIError
    true
  end

  def warnings
    values = []
    # An advisory duplicate is a comparison worth offering and not a reason to hold
    # publication, so it reads here rather than in blockers.
    values << duplicate.recommended_action if duplicate.advisory? && !duplicate.blocking?
    values << "Founding year is missing; publishing is allowed, but add a sourced year later when one is found (never fabricate)." if changes["founded_date"].blank?
    values << "No enrichment critic verdict is recorded." if proposal.agent_details.dig("description_critic", "verdict").blank?
    values << verification_warning if verification_warning
    values << "Taxonomy was not auto-accepted." if taxonomy_suggestion.present? && !taxonomy_suggestion["accepted"]
    values
  end

  def score
    checks = [
      changes["name"].present?,
      changes["main_url"].present?,
      changes["location"].present?,
      changes["founded_date"].present?,
      changes["description"].present?,
      changes["category_id"].present?,
      proposal.revenue_models_present?(changes),
      proposal.target_clients_present?(changes),
      !weak_description?,
      !duplicate.blocking?
    ]
    ((checks.count(true).to_f / checks.size) * 100).round
  end

  def weak_description?
    description = changes["description"].to_s.squish
    description.split.size < 10 ||
      description.match?(/\bprovides or supports legal technology services\b/i) ||
      description.match?(/\b(listed in TechIndex|directory metadata|available records|source data)\b/i)
  end

  def low_confidence_taxonomy?
    return false if taxonomy_suggestion.blank?
    return false if proposal.missing_taxonomy_field_keys(changes).any?

    !taxonomy_suggestion["accepted"]
  end

  def taxonomy_suggestion
    @taxonomy_suggestion ||= proposal.agent_details["taxonomy_suggestion"]
  end

  def usable_web_results
    @usable_web_results ||= Array(proposal.agent_details.dig("web_research", "results")).select do |result|
      result["url"].present? || result["title"].present? || result["snippet"].present?
    end
  end

  # Pages enrichment actually retrieved from the company's own site or profiles.
  def site_evidence_pages
    @site_evidence_pages ||= Array(proposal.agent_details.dig("site_evidence", "pages"))
  end

  def fetched_pages
    @fetched_pages ||= site_evidence_pages.select { |page| page["status"] == "fetched" && page["text"].to_s.strip.present? }
  end

  def fetch_blocked?
    fetched_pages.empty? && site_evidence_pages.any? { |page| page["status"].in?(%w[blocked error]) }
  end

  def fetch_block_reasons
    site_evidence_pages.select { |page| page["status"].in?(%w[blocked error]) }
                       .map { |page| page["reason"].presence || page["status"] }
                       .uniq.first(3)
  end

  def independent_evidence_count
    @independent_evidence_count ||= fetched_pages.size + usable_web_results.size
  end

  # Deliberately separate from the completeness score. The score answers "are the
  # fields filled in"; this answers "did anyone check" — and only the second is a
  # reason to trust the record.
  def verification_state
    independent_evidence_count.positive? ? "evidence_backed" : "unverified"
  end

  # Surfaced as a warning rather than a blocker: a reviewer looking at the record may
  # publish it on their own judgement, but this is what stops anything autonomous doing
  # so, and it tells them what was not checked.
  def verification_warning
    return nil if description_verified?
    return nil if changes["description"].blank?
    return nil if DescriptionVerificationService.blocking?(description_verification)

    reason = description_verification.present? ? description_verification["accuracy_assessment"].presence : "verification has not run"
    "This description has not been verified against the company's own pages#{" — #{reason}" if reason} It can be published by hand, but not automatically."
  end

  def usable_source_evidence_count
    @usable_source_evidence_count ||= [
      proposal.source_payload["crunchbase_url"],
      proposal.source_payload["linkedin_url"],
      proposal.source_payload["source_description"],
      proposal.source_payload["full_source_description"],
      changes["crunchbase_url"],
      changes["linkedin_url"],
      changes["source_url"]
    ].compact_blank.size
  end
end
