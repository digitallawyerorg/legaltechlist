module Admin
  class CompanyProposalsController < BaseController
    def index
      @status = params[:status].presence || "pending_review"
      @company_proposals = proposals_scope.recent.page(params[:page]).per(25)
      @proposal_quality_reports = proposal_quality_reports_for(@company_proposals)
      @status_counts = proposal_filter_counts
      @review_cockpit_counts = review_cockpit_counts
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
      CompanyProposalEnrichmentService.call(proposal: @company_proposal, admin_user: current_admin_user)

      redirect_to custom_admin_company_proposal_path(@company_proposal), notice: "Proposal enriched for review. No company records were changed."
    end

    def approve
      load_proposal
      publish = params[:publish] == "1"

      if @company_proposal.user_suggestion?
        company = CompanyProposalApplyUpdateService.call(proposal: @company_proposal, admin_user: current_admin_user, publish: publish)
        SlackNotifier.contribution_decision(@company_proposal, decision: "approved", admin_user: current_admin_user, note: "Applied update to #{company.name}.")
        redirect_to custom_admin_company_review_path(company), notice: "Update applied to #{company.name}."
      else
        company = CompanyProposalApprovalService.call(proposal: @company_proposal, admin_user: current_admin_user, duplicate_override: params[:duplicate_override] == "1", publish: publish)
        SlackNotifier.contribution_decision(@company_proposal, decision: "approved", admin_user: current_admin_user, note: publish ? "Published #{company.name}." : "Draft created for #{company.name}.")
        notice = publish ? "#{company.name} was approved and published." : "Invisible company draft created for #{company.name}. Review once more before publication."
        redirect_to custom_admin_company_review_path(company), notice: notice
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

    def reject
      load_proposal
      @company_proposal.update!(
        status: "rejected",
        admin_user: current_admin_user,
        rejection_reason: params[:rejection_reason].presence || "Rejected from admin proposal review.",
        reviewed_at: Time.current,
        rejected_at: Time.current
      )

      SlackNotifier.contribution_decision(@company_proposal, decision: "rejected", admin_user: current_admin_user, note: @company_proposal.rejection_reason)

      redirect_to custom_admin_company_proposal_path(@company_proposal), notice: "Proposal rejected without changing company data."
    end

    private

    def load_proposal
      @company_proposal = CompanyProposal.find(params[:id])
      @source_payload = @company_proposal.source_payload || {}
      @final_changes = @company_proposal.editable_changes
      @duplicate_signals = @company_proposal.duplicate_signals || {}
      @agent_details = @company_proposal.agent_details || {}
    end

    def review_cockpit_counts
      quality_reports = proposal_quality_reports_for(CompanyProposal.all)
      {
        "ready" => quality_reports.count { |_id, report| report["publish_ready"] },
        "needs_revision" => CompanyProposal.where(status: "needs_revision").count,
        "duplicate_blocked" => duplicate_scope.count,
        "missing_taxonomy" => quality_reports.count { |_id, report| taxonomy_fields_missing?(report) },
        "missing_description" => quality_reports.count { |_id, report| Array(report["missing_required_fields"]).include?("description") },
        "published" => CompanyProposal.published.count
      }
    end

    def proposals_scope
      case @status
      when "pending_review"
        CompanyProposal.pending_review
      when "duplicate"
        duplicate_scope
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
        "pending_review" => CompanyProposal.pending_review.count,
        "duplicate" => duplicate_scope.count,
        "missing_taxonomy" => missing_taxonomy_scope.count,
        "ready" => ready_proposal_ids.size,
        "auto_drafted" => CompanyProposal.approved_to_draft.where.not(company_id: nil).count,
        "user_submissions" => CompanyProposal.user_submissions.pending_review.count,
        "user_contributions" => CompanyProposal.user_contributions.pending_review.count,
        "user_suggestions" => CompanyProposal.user_suggestions.pending_review.count,
        "published" => CompanyProposal.published.count,
        "rejected" => CompanyProposal.rejected.count
      }
    end

    def duplicate_scope
      CompanyProposal.where("jsonb_array_length(COALESCE(duplicate_signals->'name_matches', '[]'::jsonb)) > 0 OR jsonb_array_length(COALESCE(duplicate_signals->'domain_matches', '[]'::jsonb)) > 0")
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
