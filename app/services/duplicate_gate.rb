# The one duplicate gate. Every path that drafts, publishes, applies or auto-applies a
# proposal asks this unit, and a blocking match stops that path here.
#
# The check used to live in four places that each did it their own way: intake did not
# consult the detector at all, the discovery row processor branched on the model helper,
# the approval service raised its own message, and the MCP approval tool folded the answer
# into a boolean beside the quality gate — then skipped the whole thing for user
# suggestions, which is how a suggestion published over a blocking duplicate onto a live
# record. Scattering the check meant "is this a duplicate" had as many answers as there
# were callers, and adding an ingestion path meant remembering to ask.
#
# So the decision, the reviewer-facing wording, the routing transition and the refusal all
# live here, and the identity keys behind them live in CompanyIdentityMatcher. Callers
# choose how to stop, not whether to:
#
#   check    resolve the answer and read it (reports, list views, the quality gate)
#   route!   move the proposal into the reviewer's duplicate queue
#   enforce! route! and refuse, for a path that was about to write
#
# Blocking is never a rejection. A duplicate is a comparison a human has to make, so the
# submission stays open with the canonical record named on it.
class DuplicateGate
  # Statuses that still read as open work, and so can be moved into the duplicate queue.
  # A proposal that already minted a company keeps its own status; this gate refuses
  # writes, it never un-publishes or reopens a resolved record.
  ROUTABLE_STATUSES = %w[pending ready_for_review needs_revision].freeze

  FALLBACK_ACTION = "Resolve the duplicate match against the existing record before publishing."

  # An ArgumentError subclass on purpose: the admin controller, the batch service and both
  # MCP tools already turn ArgumentError into a structured "blocked" result, so every
  # caller reports the refusal instead of crashing on it.
  class Blocked < ArgumentError
    attr_reader :signals

    def initialize(message, signals: {})
      @signals = signals || {}
      super(message)
    end
  end

  class Decision
    attr_reader :proposal, :signals

    def initialize(proposal:, signals:, overridden: false)
      @proposal = proposal
      @signals = signals || {}
      @overridden = overridden
    end

    def overridden? = @overridden

    # The override is a human saying "these are genuinely different companies". It clears
    # the gate without erasing what the gate saw — the evidence is already recorded.
    def blocking? = signals["blocking"] == true && !overridden?

    # Something matched, but on a single loose key with nothing independent agreeing.
    # A reviewer is told; a write by a human is not stopped.
    def advisory? = signals["advisory"] == true && !overridden?

    # What an UNATTENDED path asks. A human reading an advisory match can weigh it and
    # proceed; a machine cannot, and the cost of it being wrong is not symmetric — a
    # demotion that turns into an auto-published second row, or an auto-rejected real
    # submission, is worse than the false positive the demotion removed. So automation
    # stops on advisory too, and stopping means leaving the record for a human rather
    # than disposing of it.
    def holds_automation? = blocking? || advisory?

    def recommended_action = signals["recommended_action"].presence || FALLBACK_ACTION

    def matches = Array(signals["name_matches"]) + Array(signals["domain_matches"])

    def blocking_matches = matches.select { |match| surfacing(match) == CompanyIdentityMatcher::SURFACING_BLOCKING }

    def advisory_matches = matches.select { |match| surfacing(match) == CompanyIdentityMatcher::SURFACING_ADVISORY }

    def proposal_matches = Array(signals["proposal_matches"])

    def blocking_proposal_matches = proposal_matches.select { |match| surfacing(match) == CompanyIdentityMatcher::SURFACING_BLOCKING }

    def advisory_proposal_matches = proposal_matches.select { |match| surfacing(match) == CompanyIdentityMatcher::SURFACING_ADVISORY }

    # The published row is the one to resolve against when there is one; otherwise the
    # first match, which may be a hidden draft the reviewer needs to be told about.
    #
    # Only a blocking match can be named here. An advisory hit is a comparison offered,
    # not a canonical record: writing one into the routing entry would tell a reviewer
    # to resolve against a record the gate itself declined to stop the write for.
    def canonical_match = blocking_matches.find { |match| match["visible"] } || blocking_matches.first

    def canonical_proposal_match = blocking_proposal_matches.first

    # Hits written before this shape existed carry no surfacing value. They were all
    # blocking when they were written, which is what the absence means — never advisory.
    def surfacing(match) = match["surfacing"].presence || CompanyIdentityMatcher::SURFACING_BLOCKING

    def message = "Resolve the duplicate before approval: #{recommended_action}"
  end

  # refresh resolves against the index and the open queue as they are NOW. Anything about
  # to write passes refresh: true — a sibling proposal may have been created or resolved
  # since this proposal was last looked at. A list view rendering many rows reuses what it
  # already resolved.
  #
  # record_evidence writes the append-only note of what the gate saw, because the live
  # view forgets: resolving one of two twins drops it from the comparison set, so the
  # survivor reads clean and a later reader concludes the write ran on an uncontested row.
  # Reporting callers pass false; anything that acts on the answer leaves it on.
  def self.check(proposal, override: false, refresh: true, record_evidence: true)
    signals = proposal.current_duplicate_signals(refresh: refresh)
    # Advisory decisions are recorded too: the live view forgets either way, and "the
    # gate looked and decided this was not strong enough" is exactly the disposition a
    # later reader needs to be able to audit.
    proposal.record_duplicate_evidence!(signals) if record_evidence
    Decision.new(proposal: proposal, signals: signals, overridden: ActiveModel::Type::Boolean.new.cast(override))
  end

  # Duplicate resolution, not the normal review flow: the submission stays open with the
  # canonical record named on it, and no automated step touches it afterwards. It lands in
  # the admin duplicate queue, which selects live over open work, where the two records can
  # be compared and merged. That is the decision this shape of submission actually needs,
  # and it needs no status of its own.
  def self.route!(decision)
    proposal = decision.proposal
    return decision unless proposal.persisted?

    attributes = {
      duplicate_signals: decision.signals,
      agent_details: proposal.agent_details.merge("duplicate_routing" => routing_entry(decision))
    }

    if proposal.status.in?(ROUTABLE_STATUSES)
      attributes[:status] = "ready_for_review"
      # Only stamped when it is not already set. The value records when a human looked at
      # the record, and a reopened resubmission arrives here carrying a real one
      # (UserContributionIntakeService#reopen_returned! keeps it on purpose); overwriting
      # it with a machine timestamp would lose that. Either way it stays present, so the
      # enrichment lock it drives (CompanyProposalEnrichmentService#locked_reason) holds.
      attributes[:reviewed_at] = Time.current if proposal.reviewed_at.blank?
      attributes[:reviewer_notes] = routed_notes(proposal, decision.recommended_action)
    end

    proposal.update!(attributes)
    decision
  end

  # Called by a path that was about to draft, publish, apply or overwrite. Blocking stops
  # it: the record is routed to resolution first, so stopping leaves it somewhere a human
  # will see it rather than merely failing.
  def self.enforce!(proposal, override: false, refresh: true)
    decision = check(proposal, override: override, refresh: refresh)
    return decision unless decision.blocking?

    route!(decision)
    raise Blocked.new(decision.message, signals: decision.signals)
  end

  def self.routing_entry(decision)
    {
      "routed_at" => Time.current.utc.iso8601,
      "confidence" => decision.signals["confidence"],
      "canonical_company_id" => decision.canonical_match&.dig("id"),
      "canonical_company_visible" => decision.canonical_match&.dig("visible"),
      "canonical_proposal_id" => decision.canonical_proposal_match&.dig("proposal_id"),
      "recommended_action" => decision.recommended_action
    }.compact
  end

  # Re-routing the same proposal (a second apply attempt, a reviewer retrying an approval)
  # must not stack the same paragraph up the notes field.
  def self.routed_notes(proposal, action)
    note = "Routed to duplicate resolution. #{action}"
    existing = proposal.reviewer_notes.to_s
    return existing if existing.include?(note)

    [existing.presence, note].compact.join("\n")
  end

  private_class_method :routing_entry, :routed_notes
end
