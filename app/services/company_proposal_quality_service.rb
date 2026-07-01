class CompanyProposalQualityService
  REQUIRED_FIELDS = %w[name main_url location founded_date description category_id business_model_id target_client_id].freeze

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
      "blockers" => blockers,
      "warnings" => warnings,
      "usable_web_evidence_count" => usable_web_results.size,
      "usable_source_evidence_count" => usable_source_evidence_count,
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

  def scalar_field_blank?(field)
    return false if field.in?(%w[business_model_id target_client_id])

    changes[field].blank?
  end

  def blockers
    @blockers ||= begin
      values = []
      values << "Resolve duplicate signals before publishing." if proposal.duplicate_blocking?
      values << "Complete required fields before publishing: #{missing_required_fields.map(&:humanize).to_sentence}." if missing_required_fields.any?
      values << "Review low-confidence taxonomy before publishing." if low_confidence_taxonomy?
      values << "Revise weak or generic description before publishing." if weak_description?
      values << "Description appears to copy the source text." if copied_source_description?
      values << "Possible spam or malformed public submission — requires human review before publishing." if spam_suspected?
      values
    end
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
    values << "No usable source or web evidence is attached." if usable_web_results.empty? && usable_source_evidence_count.zero?
    values << "No enrichment critic verdict is recorded." if proposal.agent_details.dig("description_critic", "verdict").blank?
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
      !proposal.duplicate_blocking?
    ]
    ((checks.count(true).to_f / checks.size) * 100).round
  end

  def weak_description?
    description = changes["description"].to_s.squish
    description.split.size < 10 ||
      description.match?(/\bprovides or supports legal technology services\b/i) ||
      description.match?(/\b(listed in TechIndex|directory metadata|available records|source data)\b/i)
  end

  def copied_source_description?
    source_description = proposal.source_payload["source_description"].to_s.squish
    full_source_description = proposal.source_payload["full_source_description"].to_s.squish
    description = changes["description"].to_s.squish
    description.present? && ([source_description, full_source_description].compact_blank.any? { |source| description.casecmp?(source) })
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
