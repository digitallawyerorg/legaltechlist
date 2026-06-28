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

    case triage["verdict"]
    when "reject"
      reject_proposal!(triage["reason"])
      return result("rejected", triage["reason"])
    when "review"
      proposal.update!(status: "ready_for_review", reviewed_at: Time.current)
      return result("ready_for_review", triage["reason"])
    end

    if proposal.user_suggestion?
      apply_suggestion_interpretation!
      proposal.update!(status: "ready_for_review", reviewed_at: Time.current)
      return result("ready_for_review", "Suggestion interpreted for human review.")
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

  def apply_suggestion_interpretation!
    delta = UserSuggestionInterpretationService.call(proposal: proposal)
    return if delta.blank?

    merged = proposal.final_changes.merge(delta)
    proposal.update!(
      proposed_changes: proposal.proposed_changes.merge(delta),
      final_changes: merged,
      agent_details: proposal.agent_details.merge("suggestion_interpretation" => { "delta" => delta })
    )
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

  def result(status, message, company = nil)
    { "status" => status, "message" => message, "company_id" => company&.id }
  end

  def skip(reason)
    { "status" => "skipped", "message" => reason }
  end
end
