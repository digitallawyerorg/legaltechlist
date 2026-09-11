module Admin
  class CompanyReviewsController < BaseController
    include ReviewQueueContext
    def show
      @company = Company.includes(:category, :secondary_category, :successor_company, :business_models, :target_clients, :target_client, :tags).find(params[:id])
      @duplicate_matches = CompanyDuplicateSurface.call(@company)
      @company_pipeline_runs = PipelineRun.for_company(@company).recent.limit(10)
      @agent_review = AgentReviewPacket.latest_agent_review_for(@company)
      @queue = returning_queue_context
      @duplicate_review = AgentReviewPacket.latest_duplicate_review_for(@company)
    end

    def create_agent_review
      company = Company.find(params[:id])
      CompanyAgentReviewService.call(company: company, reviewer: current_admin_user.email, notes: "Triggered from custom company review page")

      redirect_to record_path(company, anchor: "agent-review"),
                  notice: "Agent review complete for #{company.name}. The findings are below."
    end

    def create_next_description_review
      company = Company.description_review_candidates.order(updated_at: :asc).first
      return redirect_to custom_admin_companies_path(review_signal: "description_review"), alert: "No description review candidates found." unless company

      run = CompanyAgentReviewService.call(company: company, reviewer: current_admin_user.email, notes: "Triggered from next description review queue")

      redirect_to custom_admin_agent_review_path(run), notice: "Description review created for #{company.name}."
    end

    def create_duplicate_review
      company = Company.find(params[:id])
      DuplicateDomainReviewService.call(company: company, reviewer: current_admin_user.email, notes: "Triggered from custom company review page")

      redirect_to record_path(company, anchor: "duplicate-review"),
                  notice: "Duplicate review complete for #{company.name}. The findings are below."
    end

    def create_next_duplicate_domain_review
      company = Company.duplicate_domain_candidates.order(updated_at: :asc).first
      return redirect_to custom_admin_companies_path(review_signal: "duplicate_domain"), alert: "No duplicate-domain candidates found." unless company

      run = DuplicateDomainReviewService.call(company: company, reviewer: current_admin_user.email, notes: "Triggered from next duplicate-domain review queue")

      redirect_to custom_admin_agent_review_path(run), notice: "Duplicate-domain review created for #{company.name}."
    end

    def mark_review
      company = Company.find(params[:id])
      decision = params[:decision].to_s
      CompanyReviewMarkService.call(
        company: company,
        decision: decision,
        admin_user: current_admin_user,
        instructions: params[:contributor_instructions],
        fields: params[:contributor_fields],
        context: { queue: returning_queue_context, entry_point: params[:entry_point] }
      )

      # A record handed back to its contributor has left this reviewer's queue, so land
      # on the queue rather than the record they no longer need to act on.
      if decision == "return_to_contributor"
        return redirect_to queue_redirect_path(custom_admin_companies_path(review_state: "awaiting_contributor")),
                           notice: "#{company.name} was returned to its contributor and is no longer in the review queue."
      end

      if decision.in?(%w[verified reject])
        return redirect_to queue_redirect_path(custom_admin_companies_path),
                           notice: "#{mark_review_notice(decision, company.name)} It has left the review queue."
      end

      # Still the reviewer's to pick up, so they stay on it — with the queue they came
      # from still attached, rather than having to rebuild their filters to carry on.
      redirect_to record_path(company), notice: mark_review_notice(decision, company.name)
    rescue CompanyReviewMarkService::NotConfirmed => e
      # Reported success, saved nothing. Saying so is the whole point: a reviewer who
      # is told the decision landed will not make it again.
      redirect_to record_path(company), alert: e.message
    rescue ArgumentError => e
      redirect_to record_path(company), alert: e.message
    end

    private

    # The record, with the queue the reviewer arrived from still attached. An action
    # that leaves them on the record must not cost them their place in the list.
    def record_path(company, anchor: nil)
      custom_admin_company_review_path(company.id, anchor: anchor, queue: returning_queue_context.presence)
    end

    def mark_review_notice(decision, company_name)
      case decision
      when "verified" then "#{company_name} marked as verified."
      when "needs_work" then "#{company_name} marked as needing more review."
      when "reject" then "#{company_name} rejected and hidden."
      else "Review status updated for #{company_name}."
      end
    end

  end
end
