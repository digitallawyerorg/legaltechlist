# The review trail on a proposal: who looked at it, when, and what they concluded.
#
# Before this existed a proposal only had a status, and "a reviewer opened this, checked
# it and decided to leave it as it is" did not change the status at all. So a proposal
# that had been reviewed and deliberately left alone looked exactly like one nobody had
# touched, and the next pass (a person, Claude or Jane) triaged it all over again.
#
# Entries are append-only and capped, and live in agent_details["review_log"] next to
# the rest of the proposal's history. Reading the latest entry is how both the admin
# queue and the MCP tools say "Reviewed — no change | hafez@… | 2026-11-09".
class CompanyProposalReviewLog
  OUTCOME_NO_CHANGE = "no_change".freeze
  OUTCOME_NEEDS_MORE_WORK = "needs_more_work".freeze
  OUTCOME_REOPENED = "reopened".freeze

  # Outcomes a reviewer can record by hand. "reopened" is written by the reopen action.
  RECORDABLE_OUTCOMES = [OUTCOME_NO_CHANGE, OUTCOME_NEEDS_MORE_WORK].freeze
  OUTCOMES = (RECORDABLE_OUTCOMES + [OUTCOME_REOPENED]).freeze

  LABELS = {
    OUTCOME_NO_CHANGE => "Reviewed — no change",
    OUTCOME_NEEDS_MORE_WORK => "Needs more work",
    OUTCOME_REOPENED => "Reopened for review"
  }.freeze

  MAX_ENTRIES = 50

  def self.record!(proposal, outcome:, reviewer:, note: nil, via: "admin")
    outcome = outcome.to_s
    raise ArgumentError, "Unknown review outcome '#{outcome}'. Use one of: #{OUTCOMES.join(', ')}" unless OUTCOMES.include?(outcome)
    raise ArgumentError, "#{proposal.display_name} is #{proposal.status.humanize.downcase} and cannot be reviewed. Reopen it first." if proposal.terminal? && outcome != OUTCOME_REOPENED

    note = note.to_s.strip.presence
    raise ArgumentError, "Say what still needs doing when recording 'needs more work'." if outcome == OUTCOME_NEEDS_MORE_WORK && note.nil?

    entry = {
      "outcome" => outcome,
      "reviewer" => reviewer.to_s.strip.presence || "unknown",
      "reviewed_at" => Time.current.utc.iso8601,
      "status" => proposal.status,
      "note" => note,
      "via" => via
    }.compact

    attributes = {
      agent_details: proposal.agent_details.merge("review_log" => (entries(proposal) + [entry]).last(MAX_ENTRIES)),
      reviewed_at: Time.current
    }
    # Needs more work is a statement about the record, so the queue should say it too.
    attributes[:status] = "needs_revision" if outcome == OUTCOME_NEEDS_MORE_WORK && proposal.status.in?(%w[pending ready_for_review])
    proposal.update!(attributes)
    entry
  end

  def self.entries(proposal)
    details = proposal.agent_details.is_a?(Hash) ? proposal.agent_details : {}
    Array(details["review_log"]).select { |entry| entry.is_a?(Hash) }
  end

  def self.latest(proposal)
    entries(proposal).last
  end

  # "Reviewed — no change | hafez@legal.io | 2026-11-09"
  def self.label(entry)
    return nil if entry.blank?

    date = Time.zone.parse(entry["reviewed_at"].to_s)&.to_date&.iso8601
    [LABELS[entry["outcome"]] || entry["outcome"].to_s.humanize, entry["reviewer"], date].compact_blank.join(" | ")
  end
end
