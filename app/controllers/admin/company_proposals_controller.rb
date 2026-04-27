module Admin
  class CompanyProposalsController < BaseController
    def index
      @status = params[:status].presence || "pending_review"
      @company_proposals = proposals_scope.recent.page(params[:page]).per(25)
      @status_counts = {
        "pending_review" => CompanyProposal.pending_review.count,
        "pending" => CompanyProposal.where(status: "pending").count,
        "ready_for_review" => CompanyProposal.where(status: "ready_for_review").count,
        "needs_revision" => CompanyProposal.where(status: "needs_revision").count,
        "approved_to_draft" => CompanyProposal.approved_to_draft.count,
        "rejected" => CompanyProposal.rejected.count
      }
    end

    def show
      load_proposal
    end

    def edit
      load_proposal
    end

    def update
      load_proposal
      @company_proposal.assign_attributes(proposal_notes_params)
      @company_proposal.final_changes = sanitized_final_changes
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
      company = CompanyProposalApprovalService.call(proposal: @company_proposal, admin_user: current_admin_user, duplicate_override: params[:duplicate_override] == "1")

      redirect_to custom_admin_company_review_path(company), notice: "Invisible company draft created for #{company.name}. Review once more before publication."
    rescue ActiveRecord::RecordInvalid, ArgumentError => e
      redirect_to custom_admin_company_proposal_path(@company_proposal), alert: e.message
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

    def proposals_scope
      case @status
      when "pending_review"
        CompanyProposal.pending_review
      when *CompanyProposal::STATUSES
        CompanyProposal.where(status: @status)
      else
        CompanyProposal.all
      end
    end

    def proposal_notes_params
      params.require(:company_proposal).permit(:reviewer_notes)
    end

    def sanitized_final_changes
      changes = params.require(:company_proposal).permit(final_changes: CompanyProposal::EDITABLE_COMPANY_FIELDS)["final_changes"] || {}
      changes.to_h.slice(*CompanyProposal::EDITABLE_COMPANY_FIELDS)
    end
  end
end
