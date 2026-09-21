# Returning a proposal to its contributor, without minting a company row first.
#
# A reviewer who found a submission plausible but incomplete had to click Approve Draft —
# which creates a company — and only then hand the record back from the Company Tab via
# CompanyReviewMarkService#return_to_contributor!. That left a company draft nobody asked
# for and moved the record onto the Company Tab before it was ready. This is the same
# action taken one step earlier, on the proposal itself, so nothing is created to undo.
#
# Read as a sibling of CompanyReviewMarkService#return_to_contributor!: same request
# shape, same appended history, same read-back before reporting success.
class CompanyProposalReturnService
  # The state an outstanding request sits in, in the same vocabulary the company-side
  # return uses (CompanyReviewMarkService::RETURNED_STATUS), so one grep finds both.
  AWAITING_STATE = "awaiting_contributor".freeze

  # The status a returned proposal carries. needs_revision already exists, is already
  # inside scope :pending_review, and is already one of the statuses the approval path
  # will move (CompanyProposalApprovalService::OPEN_STATUSES), so the round trip needs
  # no new state — only the Review Tab's default view hides an outstanding request.
  RETURNED_PROPOSAL_STATUS = "needs_revision".freeze

  # Statuses from which a return is the reviewer's call to make. A record that has been
  # approved or rejected has left the review queue, and handing it back from here would
  # contradict a decision someone already took.
  RETURNABLE_STATUSES = %w[pending ready_for_review needs_revision].freeze

  # Raised when the write reported success but the record does not hold the requested
  # values once read back. The caller must report a failure rather than a success: a
  # reviewer told a decision landed when it did not will not make it a second time.
  class NotConfirmed < StandardError
    attr_reader :proposal, :unconfirmed

    def initialize(proposal, unconfirmed)
      @proposal = proposal
      @unconfirmed = unconfirmed
      super("The system reported success, but the value was not saved: #{unconfirmed.map { |field, pair| "#{field} was requested as #{pair['requested'].inspect} and reads back as #{pair['saved'].inspect}" }.join('; ')}.")
    end
  end

  def self.call(proposal:, admin_user: nil, instructions: nil, fields: nil)
    new(proposal: proposal, admin_user: admin_user, instructions: instructions, fields: fields).call
  end

  def initialize(proposal:, admin_user: nil, instructions: nil, fields: nil)
    @proposal = proposal
    @admin_user = admin_user
    @instructions = instructions.to_s.strip
    @fields = Array(fields).map(&:to_s).reject(&:blank?)
  end

  def call
    raise ArgumentError, "Say what the contributor needs to correct or provide." if instructions.blank?
    raise ArgumentError, "A rejected proposal cannot be returned to its contributor: it has already left the review queue. Reopen it first." if proposal.status == "rejected"
    raise ArgumentError, "This proposal has already been approved (#{proposal.status}), so it has left the review queue. Return the company record to its contributor instead." if proposal.status.in?(%w[approved_to_draft published])
    raise ArgumentError, "A proposal with status #{proposal.status} cannot be returned to its contributor." unless proposal.status.in?(RETURNABLE_STATUSES)

    request = contributor_request

    requested = {
      "status" => RETURNED_PROPOSAL_STATUS,
      "current_contributor_request" => request
    }

    proposal.update!(
      status: RETURNED_PROPOSAL_STATUS,
      admin_user: admin_user,
      reviewed_at: Time.current,
      # History is appended, never replaced, so earlier rounds stay readable.
      agent_details: append_history(request)
    )

    # The record is read back rather than trusted: an in-memory object reports whatever
    # was assigned to it, which is not evidence that the database accepted it.
    proposal.reload
    unconfirmed = requested.reject { |field, value| saved_value(field) == value }
                           .each_with_object({}) do |(field, value), memo|
      memo[field] = { "requested" => value, "saved" => saved_value(field) }
    end
    raise NotConfirmed.new(proposal, unconfirmed) if unconfirmed.any?

    SlackNotifier.contribution_decision(proposal, decision: "returned_to_contributor", admin_user: admin_user, note: instructions)

    # No ReviewerActionAudit row: that audit is keyed on a company (it names the run
    # after company.name and writes details["company_id"], which is what
    # PipelineRun.for_company reads), and the whole point of this action is that no
    # company exists yet. The full request history lives on agent_details instead.

    proposal
  end

  # The request as it was written, for callers that want to name the contributor it was
  # parked for without re-reading agent_details.
  def contributor_request
    @contributor_request ||= {
      "requested_at" => Time.current.utc.iso8601,
      "requested_by" => admin_user&.email,
      "instructions" => instructions,
      "fields" => fields,
      # Unlike a company row, a proposal carries its own submitter, so there is nothing
      # to look up and nothing to guess at.
      "contributor_email" => proposal.submitter_email.presence,
      "state" => AWAITING_STATE
    }
  end

  private

  attr_reader :proposal, :admin_user, :instructions, :fields

  def append_history(request)
    details = proposal.agent_details.is_a?(Hash) ? proposal.agent_details.deep_dup : {}
    details["contributor_requests"] = Array(details["contributor_requests"]) + [request]
    details["current_contributor_request"] = request
    details
  end

  def saved_value(field)
    field == "status" ? proposal.status : proposal.agent_details[field]
  end
end
