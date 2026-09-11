# Folds the verified improvements from a duplicate proposal into the record that is
# being kept, then rejects the proposal in favour of it.
#
# Two kinds of write, and the difference matters.
#
# A gap fill is offered by default: the existing entry has nothing there, the field is
# not part of the entry's identity, and something was actually retrieved for the
# proposal. Nothing is lost by filling it.
#
# An override replaces a value the entry already holds, and is never offered by
# default, never recommended, and never selected for the reviewer. It exists because
# the alternative was worse: the comparison would tell a reviewer the two records
# disagreed on location — "United States" against "Las Vegas, NV, USA" — invite them to
# check the sources, and then give them nowhere to put the answer. The verification
# happened; the worse value stayed. A reviewer may now take a conflicting field, one at
# a time, and what moved is recorded with both values.
#
# Identity fields (name, main_url) are outside both: changing what an entry *is* is a
# rename or a rebrand, not a duplicate resolution.
class DuplicateMergeService
  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(proposal:, company:, fields:, admin_user:)
    @proposal = proposal
    @company = company
    @requested_fields = Array(fields).map(&:to_s)
    @admin_user = admin_user
  end

  def call
    comparison = DuplicateComparisonService.call(proposal: proposal, company: company)
    fillable = comparison["mergeable_fields"] & requested_fields
    overrides = comparison["overridable_fields"] & requested_fields
    allowed = fillable + overrides
    raise ArgumentError, "None of the selected fields can be merged into #{company.name}." if allowed.empty?

    rows = comparison["rows"].index_by { |row| row["key"] }
    applied = allowed.each_with_object({}) do |field, acc|
      row = rows[field]
      # Structurally impossible for a gap fill or an override to carry a blank — both
      # verdicts require the proposal to hold a value — but a blank write here would
      # erase a populated field on a live entry, so it is refused rather than trusted.
      next if row["proposal_value"].to_s.strip.blank?

      company.public_send("#{field}=", row["proposal_value"])
      acc[field] = {
        "from" => row["company_value"],
        "to" => row["proposal_value"],
        "kind" => overrides.include?(field) ? "override" : "gap_fill",
        "sources" => row["evidence"]
      }
    end
    raise ArgumentError, "Nothing was applied: every selected field was blank in the proposal." if applied.empty?

    # The proposal is only resolved once the record it is being resolved in favour of
    # has actually taken the change. Rejecting first would discard the evidence for a
    # write that then failed.
    ActiveRecord::Base.transaction do
      company.save!
      record_merge!(applied)
      reject_proposal!(applied)
    end

    { "company_id" => company.id, "applied" => applied, "overrides" => overrides }
  end

  private

  attr_reader :proposal, :company, :requested_fields, :admin_user

  # Provenance for a change to a live public entry: which fields moved, what they were,
  # what they became, and what supported each one.
  def record_merge!(applied)
    PipelineRun.create!(
      name: "Duplicate merge into #{company.name}",
      run_type: "duplicate_merge",
      status: "succeeded",
      agent_name: "DuplicateMergeService",
      records_processed: applied.size,
      details: {
        "company_id" => company.id,
        "proposal_id" => proposal.id,
        "merged_by" => admin_user&.email,
        "merged_at" => Time.current.utc.iso8601,
        "applied_changes" => applied,
        "overridden_fields" => applied.select { |_field, change| change["kind"] == "override" }.keys
      }
    )
  end

  # The proposal is resolved, not discarded: it keeps its rejection reason, the entry
  # that was kept, and the list of what it contributed before being closed.
  def reject_proposal!(applied)
    proposal.update!(
      status: "rejected",
      admin_user: admin_user,
      reviewed_at: Time.current,
      rejected_at: Time.current,
      rejection_reason: "Merged #{applied.keys.map(&:humanize).map(&:downcase).to_sentence} into #{company.name} (##{company.id}); that record is canonical.",
      agent_details: proposal.agent_details.merge(
        "canonical_record" => {
          "company_id" => company.id,
          "resolved_by" => admin_user&.email,
          "resolved_at" => Time.current.utc.iso8601,
          "merged_fields" => applied.keys,
          "overridden_fields" => applied.select { |_field, change| change["kind"] == "override" }.keys
        }
      )
    )
  end
end
