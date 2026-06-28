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

  def process_user_suggestion!(triage)
    apply_suggestion_interpretation!
    proposal.reload

    if auto_apply_suggestion?
      company = CompanyProposalApplyUpdateService.call(
        proposal: proposal,
        admin_user: nil,
        publish: proposal.company.visible?
      )
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
