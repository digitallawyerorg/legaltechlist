class CompanyUserSubmissionProcessorService
  def self.call(proposal:)
    new(proposal: proposal).call
  end

  def initialize(proposal:)
    @proposal = proposal
  end

  def call
    return skip("not_user_submission") unless proposal.user_submission?
    return skip("already_processed") unless proposal.status == "pending"

    triage = UserSubmissionTriageService.call(proposal: proposal)
    proposal.agent_details = proposal.agent_details.merge("triage" => triage)
    proposal.save!

    if triage["verdict"] == "reject"
      reject_proposal!(triage["reason"])
      return result("rejected", triage["reason"])
    end

    # Before anything else decides what happens to this submission: does the index
    # already hold this company? Nothing here used to ask. Triage's own duplicate rule
    # compared canonical domains against publicly visible rows only, and everything after
    # it — enrichment, the draft, the auto-publish — ran without consulting the detector
    # that the approval gate and the admin queue both use. So a submission for a company
    # already published under a later name, on another TLD, or into a hidden draft was
    # enriched and drafted as new work, and the duplicate only surfaced at approval, by
    # which point a second row existed or the submitted text had been overwritten.
    duplicate = DuplicateGate.check(proposal)
    return routed_result(DuplicateGate.route!(duplicate)) if duplicate.blocking?

    return process_user_suggestion!(triage) if proposal.user_suggestion?

    if triage["verdict"] == "review"
      proposal.update!(status: "ready_for_review", reviewed_at: Time.current)
      return result("ready_for_review", triage["reason"])
    end

    CompanyProposalEnrichmentService.call(proposal: proposal)
    proposal.reload

    quality = CompanyProposalQualityService.call(proposal)
    proposal.agent_details = proposal.agent_details.merge("quality" => quality)
    proposal.save!

    if auto_publish? && quality["publish_ready"]
      company = CompanyProposalApprovalService.call(proposal: proposal, admin_user: nil, publish: true)
      return result("published", "Auto-published after triage and enrichment.", company)
    end

    if quality["publish_ready"]
      company = create_hidden_draft!(proposal)
      return result("approved_to_draft", "Invisible draft created after enrichment.", company)
    end

    proposal.update!(status: "ready_for_review", reviewed_at: Time.current)
    result("ready_for_review", Array(quality["blockers"]).first || "Queued for human review.")
  end

  private

  attr_reader :proposal

  # A suggestion is already bound to its company, so a match against that same company is
  # the record commenting on itself, not a second listing — the matcher excludes it. Any
  # other blocking match, on either proposal type, is a submission that needs resolving
  # against an existing record before it can be treated as new. Deciding that, and moving
  # the record into the duplicate queue, is DuplicateGate's job for every path; this one
  # only translates the outcome into the result shape callers here expect.
  def routed_result(decision)
    result("duplicate_resolution", decision.recommended_action)
  end

  def process_user_suggestion!(triage)
    apply_suggestion_interpretation!
    proposal.reload

    # Interpretation rewrites the name, URL and profile links this suggestion is asking
    # for, and those are exactly what identity is matched on — so the answer from before
    # it ran is not the answer that governs the write. The gate is asked again on the
    # interpreted record, before auto-apply is even considered.
    interpreted = DuplicateGate.check(proposal)
    return routed_result(DuplicateGate.route!(interpreted)) if interpreted.blocking?

    if auto_apply_suggestion?
      begin
        company = CompanyProposalApplyUpdateService.call(
          proposal: proposal,
          admin_user: nil,
          publish: proposal.company.visible?
        )
      rescue DuplicateGate::Blocked => e
        # Reached only when a match appears between the check above and the write — a twin
        # arriving mid-run. The gate has already routed the record; report that rather
        # than announcing an approval or crashing the run.
        return result("duplicate_resolution", e.message)
      end

      SlackNotifier.contribution_decision(
        proposal,
        decision: "approved",
        admin_user: nil,
        note: "Auto-applied suggestion to #{company.name}."
      )
      return result("applied", "Suggestion auto-applied to #{company.name}.", company)
    end

    proposal.update!(status: "ready_for_review", reviewed_at: Time.current)
    message = suggestion_interpretation_delta.present? ? "Suggestion interpreted for human review." : triage["reason"].presence || "Queued for human review."
    result("ready_for_review", message)
  end

  def apply_suggestion_interpretation!
    delta = UserSuggestionInterpretationService.call(proposal: proposal)
    proposal.agent_details = proposal.agent_details.merge("suggestion_interpretation" => { "delta" => delta })
    return proposal.save! if delta.blank?

    merged = proposal.final_changes.merge(delta)
    proposal.update!(
      proposed_changes: proposal.proposed_changes.merge(delta),
      final_changes: merged,
      agent_details: proposal.agent_details
    )
  end

  def auto_apply_suggestion?
    return false unless auto_apply_suggestions?
    return false if proposal.company.blank?
    return false unless proposal.company.visible?
    return false if suggestion_interpretation_delta.blank?

    proposal.agent_details.dig("triage", "verdict").in?(%w[accept review])
  end

  def suggestion_interpretation_delta
    proposal.agent_details.dig("suggestion_interpretation", "delta").presence
  end

  def create_hidden_draft!(proposal)
    CompanyProposalApprovalService.call(proposal: proposal, admin_user: nil, publish: false)
  end

  def reject_proposal!(reason)
    proposal.update!(
      status: "rejected",
      rejection_reason: reason.presence || "Rejected by automated triage.",
      reviewed_at: Time.current,
      rejected_at: Time.current
    )
  end

  def auto_publish?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("USER_SUBMISSION_AUTO_PUBLISH", "false"))
  end

  def auto_apply_suggestions?
    ActiveModel::Type::Boolean.new.cast(
      ENV.fetch("USER_SUGGESTION_AUTO_APPLY", Rails.env.production? ? "true" : "false")
    )
  end

  def result(status, message, company = nil)
    { "status" => status, "message" => message, "company_id" => company&.id }
  end

  def skip(reason)
    { "status" => "skipped", "message" => reason }
  end
end
