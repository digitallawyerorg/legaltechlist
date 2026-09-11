# Compares a duplicate proposal against the record it matched, field by field, so a
# reviewer decides which record survives on evidence rather than on which one the
# system happened to name first.
#
# Detection and resolution are separate steps. Flagging a duplicate says "these are the
# same thing"; it says nothing about which copy is better. Before this existed the
# blocker went straight to "keep that entry and reject this", which throws away a
# proposal that may hold a newer website, a description the index lacks, or a founding
# year nobody had.
#
# Per-field verdicts:
#   identical    both hold the same value
#   only_here    the proposal has a value the existing record lacks  -> mergeable
#   only_there   the existing record has a value the proposal lacks
#   conflict     both hold values and they differ                    -> never auto-merged,
#                                                                        overridable only by
#                                                                        an explicit per-field
#                                                                        reviewer choice
#   both_blank   neither holds a value
class DuplicateComparisonService
  # Compared in the order a reviewer reads them, and deliberately limited to fields
  # where "better" is decidable from the record itself.
  FIELDS = [
    { key: "name", label: "Company name" },
    { key: "main_url", label: "Website" },
    { key: "description", label: "Description" },
    { key: "location", label: "Location" },
    { key: "founded_date", label: "Founded" },
    { key: "linkedin_url", label: "LinkedIn" },
    { key: "crunchbase_url", label: "Crunchbase" },
    { key: "status", label: "Lifecycle status" },
    { key: "total_funding_amount_usd", label: "Total funding" },
    { key: "funding_status", label: "Funding status" },
    { key: "founders", label: "Founders" }
  ].freeze

  # Fields a merge may write when the existing record has nothing there. Identity
  # fields (name, main_url) are excluded: changing what an entry *is* is a rename or a
  # rebrand, not a gap fill, and belongs to a human.
  MERGEABLE_FIELDS = %w[
    description location founded_date linkedin_url crunchbase_url
    total_funding_amount_usd funding_status founders
  ].freeze

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(proposal:, company:)
    @proposal = proposal
    @company = company
  end

  def call
    rows = FIELDS.map { |field| row_for(field) }

    {
      "proposal_id" => proposal.id,
      "company_id" => company.id,
      "company_name" => company.name,
      "rows" => rows,
      "mergeable_fields" => rows.select { |row| row["mergeable"] }.map { |row| row["key"] },
      "overridable_fields" => rows.select { |row| row["overridable"] }.map { |row| row["key"] },
      "conflicts" => rows.select { |row| row["verdict"] == "conflict" }.map { |row| row["key"] },
      "verification_state" => quality_report["verification_state"],
      "recommendation" => recommendation(rows),
      "generated_at" => Time.current.utc.iso8601
    }
  end

  private

  attr_reader :proposal, :company

  def changes
    @changes ||= proposal.editable_changes
  end

  def quality_report
    @quality_report ||= CompanyProposalQualityService.call(proposal)
  end

  def row_for(field)
    key = field[:key]
    mine = normalize(changes[key])
    theirs = normalize(company.public_send(key)) if company.respond_to?(key)

    verdict = verdict_for(mine, theirs)
    {
      "key" => key,
      "label" => field[:label],
      "proposal_value" => mine,
      "company_value" => theirs,
      "verdict" => verdict,
      # Only a gap the proposal can fill, on a field where filling it is safe, and only
      # when something was actually retrieved for this proposal. An unverified record
      # never writes to a live entry.
      "mergeable" => verdict == "only_here" && key.in?(MERGEABLE_FIELDS) && evidence_backed?,
      # A field both records hold, differently. Never merged by default and never
      # recommended — but a reviewer who has checked the sources and found the
      # proposal's value to be the better one needs somewhere to say so, or the
      # verification they just did has nowhere to go and the worse value stays.
      "overridable" => verdict == "conflict" && key.in?(MERGEABLE_FIELDS) && evidence_backed?,
      "evidence" => evidence_for(key)
    }
  end

  def verdict_for(mine, theirs)
    return "both_blank" if mine.blank? && theirs.blank?
    return "only_here" if theirs.blank?
    return "only_there" if mine.blank?
    return "identical" if comparable(mine) == comparable(theirs)

    "conflict"
  end

  def comparable(value)
    value.to_s.downcase.gsub(%r{\Ahttps?://}, "").delete_suffix("/").gsub(/[^a-z0-9]+/, " ").squish
  end

  def normalize(value)
    return nil if value.nil?
    return value if value.is_a?(Numeric)

    value.to_s.strip.presence
  end

  def evidence_backed?
    quality_report["verification_state"] == "evidence_backed"
  end

  # The retrieved pages and citations behind this proposal, so a reviewer merging a
  # value can see what supports it. Recorded on the merge for the same reason.
  def evidence_for(key)
    return [] unless key.in?(MERGEABLE_FIELDS)

    pages = Array(proposal.agent_details.dig("site_evidence", "pages"))
                .select { |page| page["status"] == "fetched" }
                .map { |page| page["final_url"].presence || page["url"] }
    citations = Array(proposal.agent_details.dig("web_research", "results")).map { |result| result["url"] }
    (pages + citations).compact_blank.uniq.first(3)
  end

  # What the reviewer should probably do, stated as a recommendation rather than an
  # instruction. Never recommends touching the live entry on an unverified proposal.
  def recommendation(rows)
    mergeable = rows.select { |row| row["mergeable"] }
    conflicts = rows.select { |row| row["verdict"] == "conflict" }

    if !evidence_backed?
      {
        "action" => "reject_duplicate",
        "summary" => "Nothing was independently retrieved for this proposal, so it cannot be used to change a live entry. Keep #{company.name} and reject this proposal, or enrich it first if you think it has something to add."
      }
    elsif mergeable.any?
      {
        "action" => "merge_then_reject",
        "summary" => "This proposal fills #{mergeable.size} gap#{'s' unless mergeable.size == 1} the existing entry has (#{mergeable.map { |row| row['label'].downcase }.to_sentence}). Merge those, then reject the proposal and keep #{company.name} as canonical.",
        "fields" => mergeable.map { |row| row["key"] }
      }
    elsif conflicts.any?
      {
        "action" => "needs_human",
        "summary" => "The two records disagree on #{conflicts.map { |row| row['label'].downcase }.to_sentence} and neither is obviously better. Check the sources, then choose per field below — nothing here is merged automatically.",
        "fields" => conflicts.select { |row| row["overridable"] }.map { |row| row["key"] }
      }
    else
      {
        "action" => "reject_duplicate",
        "summary" => "#{company.name} already holds everything in this proposal. Reject it and keep the existing entry."
      }
    end
  end
end
