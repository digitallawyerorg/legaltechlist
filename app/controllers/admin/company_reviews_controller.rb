module Admin
  class CompanyReviewsController < BaseController
    def index
      redirect_to custom_admin_company_proposals_path
    end

    def show
      @company = Company.includes(:category, :secondary_category, :successor_company, :business_models, :target_clients, :target_client, :tags).find(params[:id])
      @duplicate_domain_companies = duplicate_domain_companies
      @duplicate_name_companies = duplicate_name_companies
      @recent_pipeline_runs = PipelineRun.recent.limit(5)
    end

    def create_agent_review
      company = Company.find(params[:id])
      run = CompanyAgentReviewService.call(company: company, reviewer: current_admin_user.email, notes: "Triggered from custom company review page")

      redirect_to custom_admin_agent_review_path(run), notice: "Agent review created for #{company.name}."
    end

    def create_next_description_review
      company = Company.description_review_candidates.order(updated_at: :asc).first
      return redirect_to custom_admin_companies_path(review_signal: "description_review"), alert: "No description review candidates found." unless company

      run = CompanyAgentReviewService.call(company: company, reviewer: current_admin_user.email, notes: "Triggered from next description review queue")

      redirect_to custom_admin_agent_review_path(run), notice: "Description review created for #{company.name}."
    end

    def create_duplicate_review
      company = Company.find(params[:id])
      run = DuplicateDomainReviewService.call(company: company, reviewer: current_admin_user.email, notes: "Triggered from custom company review page")

      redirect_to custom_admin_agent_review_path(run), notice: "Duplicate-domain review created for #{company.name}."
    end

    def create_next_duplicate_domain_review
      company = Company.duplicate_domain_candidates.order(updated_at: :asc).first
      return redirect_to custom_admin_companies_path(review_signal: "duplicate_domain"), alert: "No duplicate-domain candidates found." unless company

      run = DuplicateDomainReviewService.call(company: company, reviewer: current_admin_user.email, notes: "Triggered from next duplicate-domain review queue")

      redirect_to custom_admin_agent_review_path(run), notice: "Duplicate-domain review created for #{company.name}."
    end

    private

    def duplicate_domain_companies
      domain = @company.canonical_domain.presence || @company.canonical_main_domain
      return Company.none if domain.blank?

      stored_matches = Company.where(canonical_domain: domain).where.not(id: @company.id)
      return stored_matches.order(:name) if @company.canonical_domain.present?

      candidate_ids = Company.duplicate_domain_candidate_ids
      return Company.none if candidate_ids.blank?

      Company.where(id: candidate_ids).where.not(id: @company.id).order(:name).select { |company| (company.canonical_domain.presence || company.canonical_main_domain) == domain }
    end

    def duplicate_name_companies
      normalized_name = @company.normalized_name
      return Company.none if normalized_name.blank?

      candidate_ids = Company.duplicate_name_candidate_ids
      return Company.none if candidate_ids.blank?

      Company.where(id: candidate_ids).where.not(id: @company.id).select { |company| company.normalized_name == normalized_name }
    end
  end
end
