module Admin
  class CompanyProposalsController < BaseController
    include ReviewQueueContext
    def index
      @status = params[:status].presence || "pending_review"
      @company_proposals = proposals_scope.recent.page(params[:page]).per(25)
      @proposal_quality_reports = proposal_quality_reports_for(@company_proposals)
      @status_counts = proposal_filter_counts
    end

    def show
      load_proposal
      @quality_report = CompanyProposalQualityService.call(@company_proposal)
    end

    def edit
      load_proposal
    end

    def update
      load_proposal
      @company_proposal.assign_attributes(proposal_notes_params)
      @company_proposal.final_changes = sanitized_final_changes
      @company_proposal.agent_details = @company_proposal.agent_details.merge("taxonomy_suggestion" => CompanyProposalTaxonomySuggestionService.call(source_payload: @company_proposal.source_payload, final_changes: @company_proposal.final_changes))
      @company_proposal.status = "ready_for_review" if @company_proposal.status == "pending"
      @company_proposal.reviewed_at = Time.current
      @company_proposal.admin_user = current_admin_user

      if @company_proposal.save
        redirect_to custom_admin_company_proposal_path(@company_proposal), notice: "Proposal updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def enrich
      load_proposal
      CompanyProposalEnrichmentService.call(proposal: @company_proposal, admin_user: current_admin_user, force: true)

      redirect_to custom_admin_company_proposal_path(@company_proposal), notice: "Proposal enriched for review. No company records were changed."
    rescue CompanyProposalEnrichmentService::Locked => e
      redirect_to custom_admin_company_proposal_path(@company_proposal), alert: e.message
    end

    def approve
      load_proposal
      publish = params[:publish] == "1"

      if @company_proposal.user_suggestion?
        company = CompanyProposalApplyUpdateService.call(proposal: @company_proposal, admin_user: current_admin_user, publish: publish, duplicate_override: params[:duplicate_override] == "1")
        SlackNotifier.contribution_decision(@company_proposal, decision: "approved", admin_user: current_admin_user, note: "Applied update to #{company.name}.")
        redirect_to custom_admin_company_review_path(company.id), notice: "Update applied to #{company.name}."
      else
        company = CompanyProposalApprovalService.call(proposal: @company_proposal, admin_user: current_admin_user, duplicate_override: params[:duplicate_override] == "1", publish: publish, reviewed_description_digest: params[:reviewed_description_digest])
        SlackNotifier.contribution_decision(@company_proposal, decision: "approved", admin_user: current_admin_user, note: publish ? "Published #{company.name}." : "Draft created for #{company.name}.")
        notice = publish ? "#{company.name} was approved and published." : "Invisible company draft created for #{company.name}. Review once more before publication."
        redirect_to custom_admin_company_review_path(company.id), notice: notice
      end
    rescue ActiveRecord::RecordInvalid, ArgumentError => e
      redirect_to custom_admin_company_proposal_path(@company_proposal), alert: e.message
    end

    def batch_update
      proposals = CompanyProposal.where(id: Array(params[:proposal_ids]))
      results = CompanyProposalBatchService.call(proposals: proposals, admin_user: current_admin_user, action: params[:batch_action], duplicate_override: params[:duplicate_override] == "1")
      redirect_to custom_admin_company_proposals_path(status: params[:status]), notice: "#{results.size} proposal actions completed."
    rescue ArgumentError, ActiveRecord::RecordInvalid => e
      redirect_to custom_admin_company_proposals_path(status: params[:status]), alert: e.message
    end

    # Item 3: detection and resolution are separate steps. Before resolving a duplicate,
    # show the reviewer how the two records actually compare.
    def compare_duplicate
      load_proposal
      @target = duplicate_target
      return redirect_to custom_admin_company_proposal_path(@company_proposal), alert: "No matching company to compare against." unless @target

      @comparison = DuplicateComparisonService.call(proposal: @company_proposal, company: @target)
    end

    def merge_duplicate
      load_proposal
      target = duplicate_target
      return redirect_to custom_admin_company_proposal_path(@company_proposal), alert: "No matching company to merge into." unless target

      result = DuplicateMergeService.call(proposal: @company_proposal, company: target, fields: selected_merge_fields, admin_user: current_admin_user)
      SlackNotifier.contribution_decision(@company_proposal, decision: "rejected", admin_user: current_admin_user, note: @company_proposal.rejection_reason)

      applied = result["applied"].keys.map(&:humanize).map(&:downcase).to_sentence
      replaced = result["applied"].select { |_field, change| change["kind"] == "override" }.keys
      notice = "Merged #{applied} into #{target.name}. The duplicate proposal was rejected and this record is canonical."
      notice += " #{replaced.map(&:humanize).map(&:downcase).to_sentence.upcase_first} #{'was'.pluralize(replaced.size == 1 ? 1 : 2)} replaced, not filled in — the previous values are on the merge record." if replaced.any?

      redirect_to custom_admin_company_review_path(target.id), notice: notice
    rescue ArgumentError => e
      redirect_to compare_duplicate_custom_admin_company_proposal_path(@company_proposal), alert: e.message
    end

    def reject
      load_proposal

      # Repeating a rejection is not an error worth an error page: the reviewer's
      # intent is already satisfied. Saying so and returning them to the queue beats a
      # second write that would overwrite the original reason and re-notify Slack.
      if @company_proposal.rejected?
        return redirect_to reject_return_path,
                           notice: "#{@company_proposal.display_name} was already resolved#{" on #{@company_proposal.rejected_at.to_date.to_fs(:long)}" if @company_proposal.rejected_at}. Nothing was changed."
      end

      @company_proposal.update!(
        status: "rejected",
        admin_user: current_admin_user,
        rejection_reason: params[:rejection_reason].presence || default_rejection_reason,
        reviewed_at: Time.current,
        rejected_at: Time.current,
        agent_details: @company_proposal.agent_details.merge(canonical_record_payload).compact
      )

      SlackNotifier.contribution_decision(@company_proposal, decision: "rejected", admin_user: current_admin_user, note: @company_proposal.rejection_reason)

      redirect_to reject_return_path, notice: rejection_notice
    # The status is only written inside the update above, so a refusal here leaves the
    # proposal exactly as it was — and says why, in the admin, rather than dropping the
    # reviewer on the public error page.
    rescue ActiveRecord::RecordInvalid => e
      redirect_to custom_admin_company_proposal_path(@company_proposal, queue: returning_queue_context.presence),
                  alert: "#{@company_proposal.display_name} could not be rejected: #{e.record.errors.full_messages.to_sentence.presence || e.message} Nothing was changed."
    end

    # A proposal that is plausible but incomplete is handed back to whoever submitted it
    # from here, on the proposal itself. It used to require Approve Draft first, which
    # minted a company row purely so the Company Tab's return action had something to act
    # on; nothing is created now, and the record stays a proposal.
    def return_to_contributor
      load_proposal

      service = CompanyProposalReturnService.new(
        proposal: @company_proposal, admin_user: current_admin_user,
        instructions: params[:contributor_instructions], fields: Array(params[:contributor_fields])
      )
      service.call

      redirect_to return_to_contributor_return_path, notice: return_to_contributor_notice(service.contributor_request)
    # Nothing is written before the refusals inside the service, and a write that did not
    # land raises rather than reporting success, so either way the proposal is untouched —
    # and the reviewer is told so in the admin instead of on the public error page.
    rescue ArgumentError, CompanyProposalReturnService::NotConfirmed, ActiveRecord::RecordInvalid => e
      redirect_to custom_admin_company_proposal_path(@company_proposal, queue: returning_queue_context.presence),
                  alert: "#{@company_proposal.display_name} was not returned to its contributor: #{e.message}"
    end

    private

    def return_to_contributor_return_path
      queue_redirect_path(custom_admin_company_proposals_path(status: params[:return_status].presence || "pending_review"))
    end

    def return_to_contributor_notice(request)
      contributor = request["contributor_email"].presence
      parked = contributor ? "parked for #{contributor}" : "parked with no contributor address on file"
      "#{@company_proposal.display_name} was returned to its contributor and #{parked}. No company draft was created."
    end

    # Gap fills arrive as checkboxes; a field both records hold arrives as an explicit
    # choice between keeping what the index has and taking what the proposal says, and
    # only the second of those is a write.
    def selected_merge_fields
      chosen = Array(params[:fields]).map(&:to_s)
      choices = params[:field_choice]
      choices = choices.respond_to?(:to_unsafe_h) ? choices.to_unsafe_h : choices.to_h if choices.present?
      chosen += Array(choices).select { |_field, choice| choice.to_s == "proposal" }.map { |field, _| field.to_s } if choices.present?
      chosen.uniq
    end

    def reject_return_path
      queue_redirect_path(custom_admin_company_proposals_path(status: params[:return_status].presence || "pending_review"))
    end

    # Rejecting a duplicate is only half the decision — which record survives is the
    # other half, and it has to be recorded or the next reviewer cannot tell that this
    # was resolved rather than merely discarded.
    def canonical_record_payload
      company_id = params[:duplicate_of_company_id].presence
      proposal_id = params[:duplicate_of_proposal_id].presence
      return {} if company_id.blank? && proposal_id.blank?

      {
        "canonical_record" => {
          "company_id" => company_id&.to_i,
          "proposal_id" => proposal_id&.to_i,
          "resolved_by" => current_admin_user.email,
          "resolved_at" => Time.current.utc.iso8601
        }.compact
      }
    end

    def canonical_label
      if (company_id = params[:duplicate_of_company_id].presence)
        company = Company.find_by(id: company_id)
        return company ? "#{company.name} (##{company.id})" : "company ##{company_id}"
      end
      return "proposal ##{params[:duplicate_of_proposal_id]}" if params[:duplicate_of_proposal_id].presence

      nil
    end

    def default_rejection_reason
      label = canonical_label
      label ? "Duplicate of #{label}; that record is canonical." : "Rejected from admin proposal review."
    end

    def rejection_notice
      label = canonical_label
      label ? "Rejected as a duplicate. #{label} is recorded as the canonical record." : "Proposal rejected without changing company data."
    end

    # The company this proposal is being compared against: the one the reviewer named,
    # otherwise the highest-confidence match the detector found.
    def duplicate_target
      return Company.find_by(id: params[:company_id]) if params[:company_id].present?

      matches = @company_proposal.duplicate_matches
      best = matches.find { |match| match["confidence"] == ProposalDuplicateDetectorService::CONFIDENCE_CONFIRMED } || matches.first
      Company.find_by(id: best&.dig("id"))
    end

    def load_proposal
      @company_proposal = CompanyProposal.find(params[:id])
      @source_payload = @company_proposal.source_payload || {}
      @final_changes = @company_proposal.editable_changes
      @duplicate_signals = @company_proposal.refresh_duplicate_signals!
      @queue = returning_queue_context
      @agent_details = @company_proposal.agent_details || {}
    end

    def proposals_scope
      case @status
      when "pending_review"
        # Work whose next action is a reviewer's. A proposal waiting on its contributor
        # is still pending_review — every other caller of that scope depends on it — but
        # it is nobody's review task until they answer, so it gets its own chip below
        # and reappears here the moment the request is cleared on resubmission.
        CompanyProposal.pending_review.not_awaiting_contributor
      when "awaiting_contributor"
        CompanyProposal.pending_review.awaiting_contributor
      when "duplicate"
        duplicate_scope
      when "resolved_duplicates"
        resolved_duplicate_scope
      when "missing_taxonomy"
        missing_taxonomy_scope
      when "auto_drafted"
        CompanyProposal.approved_to_draft.where.not(company_id: nil)
      when "user_submissions"
        CompanyProposal.user_submissions.pending_review
      when "user_contributions"
        CompanyProposal.user_contributions.pending_review
      when "user_suggestions"
        CompanyProposal.user_suggestions.pending_review
      when "ready"
        CompanyProposal.where(id: ready_proposal_ids)
      when *CompanyProposal::STATUSES
        CompanyProposal.where(status: @status)
      else
        CompanyProposal.all
      end
    end

    def proposal_filter_counts
      {
        "pending_review" => CompanyProposal.pending_review.not_awaiting_contributor.count,
        "awaiting_contributor" => CompanyProposal.pending_review.awaiting_contributor.count,
        "duplicate" => duplicate_blocking_ids.size,
        "missing_taxonomy" => missing_taxonomy_scope.count,
        "ready" => ready_proposal_ids.size,
        "auto_drafted" => CompanyProposal.approved_to_draft.where.not(company_id: nil).count,
        "user_submissions" => CompanyProposal.user_submissions.pending_review.count,
        "user_contributions" => CompanyProposal.user_contributions.pending_review.count,
        "user_suggestions" => CompanyProposal.user_suggestions.pending_review.count,
        "published" => CompanyProposal.published.count,
        "resolved_duplicates" => resolved_duplicate_scope.count,
        "rejected" => CompanyProposal.rejected.count
      }
    end

    # Open proposals whose duplicate state is blocking RIGHT NOW.
    #
    # This used to select on the stored duplicate_signals column with no status filter,
    # which was wrong twice over: the view returned 890 rejected and 66 published rows
    # alongside 13 pieces of open work, and the column is only rewritten when a record
    # is opened or enriched, so 11 proposals their own detail page was blocking never
    # appeared here at all. Resolving live over open work makes the overview and the
    # detail page agree by construction.
    def duplicate_scope
      CompanyProposal.where(id: duplicate_blocking_ids)
    end

    def duplicate_blocking_ids
      @duplicate_blocking_ids ||= CompanyProposal.pending_review.select do |proposal|
        proposal.duplicate_blocking?.tap { proposal.persist_duplicate_signals! }
      end.map(&:id)
    end

    # Duplicates that have been resolved. Kept out of every active queue but findable,
    # with the canonical record they were resolved in favour of.
    def resolved_duplicate_scope
      CompanyProposal.rejected.where("agent_details ? 'canonical_record'")
    end

    def missing_taxonomy_scope
      CompanyProposal.proposal_missing_taxonomy_scope
    end

    def ready_proposal_ids
      @ready_proposal_ids ||= proposal_quality_reports_for(CompanyProposal.pending_review).select { |_id, report| report["publish_ready"] }.keys
    end

    def proposal_quality_reports_for(scope)
      Array(scope).each_with_object({}) do |proposal, reports|
        reports[proposal.id] = proposal.cached_quality_report.presence || CompanyProposalQualityService.call(proposal)
      end
    end

    def proposal_notes_params
      params.require(:company_proposal).permit(:reviewer_notes)
    end

    def sanitized_final_changes
      permitted = params.require(:company_proposal).permit(final_changes: CompanyProposal::EDITABLE_COMPANY_FIELDS + [{ business_model_ids: [], target_client_ids: [] }])["final_changes"] || {}
      changes = permitted.to_h.slice(*CompanyProposal::EDITABLE_COMPANY_FIELDS)
      revenue_model_ids = Array(permitted["business_model_ids"]).map(&:presence).compact
      target_client_ids = Array(permitted["target_client_ids"]).map(&:presence).compact
      changes["business_model_ids"] = revenue_model_ids if revenue_model_ids.any?
      changes["business_model_id"] = revenue_model_ids.first if revenue_model_ids.any?
      changes["target_client_ids"] = target_client_ids if target_client_ids.any?
      changes["target_client_id"] = target_client_ids.first if target_client_ids.any?
      changes
    end

    def taxonomy_fields_missing?(report)
      (Array(report["missing_required_fields"]) & TaxonomyCompleteness::TAXONOMY_FIELD_KEYS).any?
    end
  end
end
