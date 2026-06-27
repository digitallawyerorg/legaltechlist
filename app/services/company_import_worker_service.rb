class CompanyImportWorkerService
  TERMINAL_ACTIONS = %w[already_published duplicate_merged duplicate_rejected published].freeze
  HELD_ACTIONS = %w[needs_review auto_drafted already_drafted].freeze
  STALE_AFTER = 20.minutes

  def self.loop
    new.loop
  end

  def self.drain(**kwargs)
    new(**kwargs).drain
  end

  def initialize(run_id: ENV["IMPORT_WORKER_RUN_ID"], batch_limit: ENV.fetch("IMPORT_WORKER_BATCH_LIMIT", 1).to_i, sleep_seconds: ENV.fetch("IMPORT_WORKER_SLEEP_SECONDS", 5).to_i)
    @run_id = run_id.presence
    @batch_limit = batch_limit.positive? ? batch_limit : 1
    @sleep_seconds = sleep_seconds.positive? ? sleep_seconds : 5
  end

  def loop
    Kernel.loop do
      processed = drain
      sleep sleep_seconds if processed.zero?
    end
  end

  def drain
    processed = 0
    batch_limit.times do
      row = claim_next_row
      break if row.blank?

      process_row(row)
      processed += 1
    end
    processed
  end

  private

  attr_reader :run_id, :batch_limit, :sleep_seconds

  def claim_next_row
    reset_stale_rows!

    CompanyImportRow.transaction do
      row = pending_scope.lock("FOR UPDATE SKIP LOCKED").first
      next unless row

      row.company_import_run.mark_running! unless row.company_import_run.status == "running"
      row.mark_processing!
      row
    end
  end

  def pending_scope
    scope = CompanyImportRow.pending.joins(:company_import_run).where(company_import_runs: { status: %w[pending running] })
    scope = scope.where(company_import_run_id: run_id) if run_id.present?
    scope
  end

  def process_row(row)
    candidate = refreshed_candidate(row)
    result = CompanyCandidateRowProcessorService.call(
      candidate: candidate,
      index: row.row_number - 1,
      admin_user: admin_user,
      pipeline_run_id: nil
    )
    quality = quality_for(result)
    result = publish_if_ready(result, quality)
    persist_result(row, result, quality)
    row.company_import_run.refresh_summary!
    complete_run_if_finished!(row.company_import_run)
  rescue StandardError => e
    row.mark_failed!(e)
    row.company_import_run.refresh_summary!
    complete_run_if_finished!(row.company_import_run)
  end

  def refreshed_candidate(row)
    candidate = AtlasCandidateNormalizerService.call(row.source_payload)
    row.update!(
      candidate_payload: candidate,
      source_identifier: candidate["canonical_domain"].presence || Company.normalized_name_value(candidate["name"]),
      canonical_domain: candidate["canonical_domain"]
    )
    candidate
  end

  def quality_for(result)
    proposal = CompanyProposal.find_by(id: result["proposal_id"])
    proposal ? CompanyProposalQualityService.call(proposal) : {}
  end

  def publish_if_ready(result, quality)
    return result unless result["action"].in?(%w[auto_drafted already_drafted])
    return result unless quality["publish_ready"] && Array(quality["warnings"]).empty?

    proposal = CompanyProposal.find_by(id: result["proposal_id"])
    company = proposal&.company
    return result unless company.present?

    company.update_columns(
      visible: true,
      quality_status: "source_verified",
      verification_verdict: "agent_published_source_verified",
      quality_reviewed_at: Time.current,
      human_reviewed_at: Time.current,
      updated_at: Time.current
    )
    proposal.update!(
      status: "published",
      reviewed_at: Time.current,
      approved_at: Time.current,
      reviewer_notes: [proposal.reviewer_notes, "Agent published after worker import quality gates passed."].compact_blank.join("\n")
    )
    result.merge("action" => "published", "reason" => "Published after worker import quality gates passed.", "company_id" => company.id)
  end

  def persist_result(row, result, quality)
    if result["action"] == "errored"
      row.update!(
        status: "failed",
        action: result["action"],
        company_proposal_id: result["proposal_id"],
        company_id: result["company_id"],
        result_payload: result,
        quality_report: quality,
        error_message: result["reason"],
        error_class: result["error_class"],
        finished_at: Time.current,
        locked_at: nil
      )
    elsif result["action"].in?(TERMINAL_ACTIONS)
      row.mark_completed!(result: result, quality: quality)
    elsif result["action"].in?(HELD_ACTIONS)
      row.mark_held!(result: result, quality: quality)
    else
      row.mark_held!(result: result, quality: quality)
    end
  end

  def complete_run_if_finished!(run)
    return if run.company_import_rows.where(status: %w[pending processing]).exists?

    run.company_import_rows.failed.exists? ? run.mark_failed!("One or more import rows failed.") : run.mark_succeeded!
  end

  def reset_stale_rows!
    scope = CompanyImportRow.where(status: "processing").where("locked_at < ?", STALE_AFTER.ago)
    scope = scope.where(company_import_run_id: run_id) if run_id.present?
    scope.update_all(status: "pending", locked_at: nil, updated_at: Time.current)
  end

  def admin_user
    @admin_user ||= AdminUser.first
  end
end
