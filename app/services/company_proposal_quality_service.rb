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
      "checked_at" => Time.current.utc.iso8601
    }
  end

  private

  attr_reader :proposal

  def changes
    @changes ||= proposal.editable_changes
  end

  def missing_required_fields
    REQUIRED_FIELDS.select { |field| changes[field].blank? }
  end

  def blockers
    @blockers ||= begin
      values = []
      values << "Resolve duplicate signals before publishing." if proposal.duplicate_blocking?
      values << "Complete required fields before publishing: #{missing_required_fields.map(&:humanize).to_sentence}." if missing_required_fields.any?
      values << "Review low-confidence taxonomy before publishing." if low_confidence_taxonomy?
      values << "Revise weak or generic description before publishing." if weak_description?
      values << "Description appears to copy the source text." if copied_source_description?
      values
    end
  end

  def warnings
    values = []
    values << "No usable web-search evidence is attached." if usable_web_results.empty?
    values << "No enrichment critic verdict is recorded." if proposal.agent_details.dig("description_critic", "verdict").blank?
    values << "Taxonomy was not auto-accepted." if taxonomy_suggestion.present? && !taxonomy_suggestion["accepted"]
    values
  end

  def score
    total = REQUIRED_FIELDS.size + 2
    complete = REQUIRED_FIELDS.count { |field| changes[field].present? }
    complete += 1 unless weak_description?
    complete += 1 unless proposal.duplicate_blocking?
    ((complete.to_f / total) * 100).round
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
    return false if missing_required_fields.intersect?(%w[category_id business_model_id target_client_id])

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
end
