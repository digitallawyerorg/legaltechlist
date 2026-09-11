class CompanyReviewMarkService
  DECISIONS = %w[verified needs_work reject return_to_contributor].freeze

  # A record that is potentially valid but incomplete should not have to be rejected to
  # get off the reviewer's desk. "return_to_contributor" parks it with the reviewer's
  # instructions attached and the next action belonging to the submitter, distinct from
  # "needs_work" (which the reviewer will pick up again themselves) and from "reject"
  # (which is a verdict that the record does not belong in the index).
  RETURNED_STATUS = "awaiting_contributor".freeze

  # Raised when the write reported success but the record does not hold the requested
  # values once read back. The caller must report a failure rather than a success: a
  # reviewer told a decision landed when it did not will not make it a second time.
  class NotConfirmed < StandardError
    attr_reader :company, :unconfirmed

    def initialize(company, unconfirmed)
      @company = company
      @unconfirmed = unconfirmed
      super("The system reported success, but the value was not saved: #{unconfirmed.map { |field, pair| "#{field} was requested as #{pair['requested'].inspect} and reads back as #{pair['saved'].inspect}" }.join('; ')}.")
    end
  end

  def self.call(company:, decision:, admin_user: nil, instructions: nil, fields: nil, context: {})
    new(company: company, decision: decision, admin_user: admin_user, instructions: instructions, fields: fields, context: context).call
  end

  def initialize(company:, decision:, admin_user: nil, instructions: nil, fields: nil, context: {})
    @company = company
    @decision = decision.to_s
    @admin_user = admin_user
    @instructions = instructions.to_s.strip
    @fields = Array(fields).map(&:to_s).reject(&:blank?)
    @context = context || {}
  end

  def call
    raise ArgumentError, "Unknown review decision: #{decision}" unless DECISIONS.include?(decision)

    started_at = Time.current
    previous = snapshot

    requested = begin
      apply!
    rescue StandardError => e
      audit(started_at: started_at, previous: previous, requested: {}, unconfirmed: {}, error: e)
      raise
    end

    # The record is read back rather than trusted: an in-memory object reports whatever
    # was assigned to it, which is not evidence that the database accepted it.
    company.reload
    unconfirmed = requested.reject { |attribute, value| company.public_send(attribute) == value }
                           .each_with_object({}) do |(attribute, value), memo|
      memo[attribute] = { "requested" => value, "saved" => company.public_send(attribute) }
    end
    confirmed = requested.except(*unconfirmed.keys)

    audit(started_at: started_at, previous: previous, requested: requested, confirmed: confirmed, unconfirmed: unconfirmed)
    raise NotConfirmed.new(company, unconfirmed) if unconfirmed.any?

    company
  end

  private

  attr_reader :company, :decision, :admin_user, :instructions, :fields, :context

  # Only the values that carry the decision. The timestamps written alongside them are
  # deliberately outside this set: they are evidence of when, not what was decided, and
  # comparing them back to the microsecond would fail on rounding rather than on truth.
  def apply!
    case decision
    when "verified"
      requested = { "quality_status" => "verified", "verification_verdict" => "human_confirmed" }
      company.update!(requested.merge(
        human_reviewed_at: Time.current, quality_reviewed_at: Time.current,
        verified_at: company.verified_at || Time.current
      ))
      requested
    when "needs_work"
      requested = { "quality_status" => "needs_review", "verification_verdict" => "needs_human_review" }
      company.update!(requested.merge(human_reviewed_at: Time.current, quality_reviewed_at: Time.current))
      requested
    when "reject"
      requested = { "quality_status" => "rejected", "verification_verdict" => "human_rejected", "visible" => false }
      company.update!(requested.merge(human_reviewed_at: Time.current, quality_reviewed_at: Time.current))
      requested
    when "return_to_contributor"
      return_to_contributor!
    end
  end

  def return_to_contributor!
    raise ArgumentError, "Say what the contributor needs to correct or provide." if instructions.blank?
    raise ArgumentError, "A rejected record cannot be returned to its contributor. Reopen it first." if company.quality_status == "rejected"

    request = {
      "requested_at" => Time.current.utc.iso8601,
      "requested_by" => admin_user&.email,
      "instructions" => instructions,
      "fields" => fields,
      "contributor_email" => contributor_email,
      "state" => "awaiting_contributor"
    }

    requested = {
      "quality_status" => RETURNED_STATUS,
      "verification_verdict" => "awaiting_contributor_update",
      # Taken off the public site while it is known to be incomplete, but never deleted.
      "visible" => false
    }

    company.update!(requested.merge(
      # human_reviewed_at is deliberately left alone: it records who reviewed the record,
      # and handing it back to its contributor is not that. Overwriting it erased an
      # approval that had been made five minutes earlier.
      quality_reviewed_at: Time.current,
      # History is appended, never replaced, so earlier rounds stay readable.
      quality_review: append_history(request)
    ))

    @contributor_request = request
    requested
  end

  def append_history(request)
    existing = company.quality_review.is_a?(Hash) ? company.quality_review.deep_dup : {}
    existing["contributor_requests"] = Array(existing["contributor_requests"]) + [request]
    existing["current_contributor_request"] = request
    existing
  end

  def snapshot
    {
      "quality_status" => company.quality_status,
      "verification_verdict" => company.verification_verdict,
      "visible" => company.visible,
      "review_state" => company.try(:review_state)
    }.compact
  end

  def audit(started_at:, previous:, requested:, unconfirmed:, confirmed: {}, error: nil)
    ReviewerActionAudit.record(
      company: company, action: decision, reviewer: admin_user, started_at: started_at,
      previous: previous, requested: requested, confirmed: confirmed, unconfirmed: unconfirmed,
      error: error, context: context,
      extra: {
        "contributor_message" => @contributor_request&.dig("instructions"),
        "fields_returned_to_contributor" => (fields if decision == "return_to_contributor"),
        "contributor_email" => @contributor_request&.dig("contributor_email")
      }.compact
    )
  end

  # Company rows carry no submitter of their own, so the contributor is whoever filed
  # the proposal this entry was created from.
  def contributor_email
    CompanyProposal.where(company_id: company.id).where.not(submitter_email: [nil, ""])
                   .order(created_at: :asc).limit(1).pick(:submitter_email)
  end
end
