# A durable record of what a human reviewer did to a company record.
#
# Agent writes have been audited since the curator MCP shipped — 1,664 PipelineRun rows
# and counting — while a reviewer's decision left nothing behind but a timestamp on the
# company. Who marked a record verified, what its status was beforehand, what a
# contributor was asked for, and whether the write actually landed were all
# unrecoverable after the fact. Reviewer actions now land in the same table the agent
# actions do, so one activity feed answers "what happened to this record" for both.
#
# Failures are recorded, not just successes: an action that reported success without
# saving is exactly the event worth being able to look up later.
class ReviewerActionAudit
  RUN_TYPE = "reviewer_action".freeze
  SUCCEEDED = "succeeded".freeze
  FAILED = "failed".freeze
  PARTIAL = "partial".freeze

  def self.record(...)
    new(...).record
  end

  def initialize(company:, action:, reviewer: nil, started_at: nil, previous: {}, requested: {},
                 confirmed: {}, unconfirmed: {}, error: nil, context: {}, extra: {})
    @company = company
    @action = action.to_s
    @reviewer = reviewer
    @started_at = started_at || Time.current
    @previous = previous.to_h.deep_stringify_keys
    @requested = requested.to_h.deep_stringify_keys
    @confirmed = confirmed.to_h.deep_stringify_keys
    @unconfirmed = unconfirmed.to_h.deep_stringify_keys
    @error = error
    @context = context.to_h.deep_stringify_keys
    @extra = extra.to_h.deep_stringify_keys
  end

  def record
    PipelineRun.create!(
      name: "Reviewer: #{action.humanize.downcase} — #{company.name}",
      run_type: RUN_TYPE,
      status: status,
      agent_name: reviewer_identity,
      records_processed: 1,
      started_at: started_at,
      finished_at: Time.current,
      error_message: error&.message,
      details: details
    )
  # An audit row that cannot be written must not take the reviewer's decision down
  # with it — the decision is the thing that mattered.
  rescue StandardError => e
    Rails.logger.warn("[ReviewerActionAudit] could not record #{action} on company #{company&.id}: #{e.class}: #{e.message}")
    nil
  end

  private

  attr_reader :company, :action, :reviewer, :started_at, :previous, :requested,
              :confirmed, :unconfirmed, :error, :context, :extra

  def status
    return FAILED if error.present?
    # Nothing landing is a failure; some of it landing is the case worth naming, because
    # the record is now in a state neither the reviewer nor the next reader expects.
    return FAILED if unconfirmed.any? && confirmed.empty?
    return PARTIAL if unconfirmed.any?

    SUCCEEDED
  end

  def details
    {
      # company_id is the key PipelineRun.for_company reads, so a reviewer action
      # shows up in the record's own activity list.
      "company_id" => company.id,
      "company_name" => company.name,
      "action_type" => action,
      "reviewer_identity" => reviewer_identity,
      "action_started_at" => started_at.utc.iso8601,
      "action_completed_at" => Time.current.utc.iso8601,
      "result" => status,
      "previous_values" => previous,
      "requested_values" => requested,
      "confirmed_values" => confirmed,
      "unconfirmed_values" => unconfirmed.presence,
      "fields_changed" => (requested.keys - unconfirmed.keys),
      "previous_status" => previous["quality_status"],
      "requested_status" => requested["quality_status"],
      "final_status" => confirmed["quality_status"],
      "error_details" => error&.message,
      "originating_queue" => context["queue"].presence,
      "entry_point" => context["entry_point"].presence
    }.merge(extra).compact
  end

  def reviewer_identity
    return reviewer if reviewer.is_a?(String) && reviewer.present?

    reviewer.try(:email) || "unknown"
  end
end
