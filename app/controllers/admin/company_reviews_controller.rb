module Admin
  class CompanyReviewsController < BaseController
    QUEUES = {
      "description_review" => "Description review",
      "missing_url" => "Missing URLs",
      "weak_description" => "Weak descriptions",
      "duplicate_name" => "Duplicate-name candidates",
      "duplicate_domain" => "Duplicate-domain candidates",
      "needs_review" => "Needs review",
      "rejected" => "Rejected"
    }.freeze

    def index
      @queue = params[:queue].presence
      @queue_label = QUEUES.fetch(@queue, "All companies")
      @companies = review_scope.page(params[:page]).per(25)
      @queue_counts = queue_counts
    end

    def show
      @company = Company.find(params[:id])
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
      return redirect_to custom_admin_company_reviews_path(queue: "description_review"), alert: "No description review candidates found." unless company

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
      return redirect_to custom_admin_company_reviews_path(queue: "duplicate_domain"), alert: "No duplicate-domain candidates found." unless company

      run = DuplicateDomainReviewService.call(company: company, reviewer: current_admin_user.email, notes: "Triggered from next duplicate-domain review queue")

      redirect_to custom_admin_agent_review_path(run), notice: "Duplicate-domain review created for #{company.name}."
    end

    private

    def review_scope
      base = Company.includes(:category, :business_model, :target_client).order(updated_at: :desc)

      case @queue
      when "description_review" then base.description_review_candidates
      when "missing_url" then base.missing_main_url
      when "weak_description" then base.weak_description
      when "duplicate_name" then base.duplicate_name_candidates
      when "duplicate_domain" then base.duplicate_domain_candidates
      when "needs_review" then base.needs_review
      when "rejected" then base.rejected_quality
      else base
      end
    end

    def queue_counts
      {
        "description_review" => Company.description_review_candidates.count,
        "missing_url" => Company.missing_main_url.count,
        "weak_description" => Company.weak_description.count,
        "duplicate_name" => Company.duplicate_name_candidate_ids.count,
        "duplicate_domain" => Company.duplicate_domain_candidate_ids.count,
        "needs_review" => Company.needs_review.count,
        "rejected" => Company.rejected_quality.count
      }
    end

    def duplicate_domain_companies
      domain = @company.canonical_domain.presence || @company.canonical_main_domain
      return Company.none if domain.blank?

      Company.where.not(id: @company.id).where.not(main_url: [nil, ""]).order(:name).select { |company| (company.canonical_domain.presence || company.canonical_main_domain) == domain }
    end

    def duplicate_name_companies
      normalized_name = @company.normalized_name
      ids = Company.duplicate_name_candidate_ids
      return Company.none if normalized_name.blank? || ids.blank?

      Company.where(id: ids).where.not(id: @company.id).select { |company| company.normalized_name == normalized_name }
    end
  end
end
