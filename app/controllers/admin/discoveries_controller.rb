module Admin
  class DiscoveriesController < BaseController
    def new
      @categories = Category.order(:name)
      @companies = Company.where(visible: true).order(:name).limit(500)
      @visible_company_count = Company.where(visible: true).count
      @discovery_types = CompanyDiscoveryService::DISCOVERY_TYPES
      @country_options = country_options
      @default_limit = CompanyDiscoveryService::DEFAULT_LIMIT
      @max_limit = CompanyDiscoveryService::DEFAULT_MAX_LIMIT
      @estimated_cost_per_search = CompanyDiscoveryService::ESTIMATED_COST_PER_SEARCH_USD
      @max_cost_usd = CompanyDiscoveryService::DEFAULT_MAX_COST_USD
      @web_search_available = web_search_available?
    end

    def create
      dry_run = params[:commit] != "Discover & queue all absent"
      queue_proposals = params[:commit] == "Discover & queue all absent"

      run = CompanyDiscoveryService.enqueue(
        discovery_type: discovery_params[:discovery_type],
        category: category_value,
        company_id: discovery_params[:company_id],
        company_name: discovery_params[:company_name],
        year: discovery_params[:year],
        country: discovery_params[:country],
        funding_year: discovery_params[:funding_year],
        limit: discovery_params[:limit],
        dry_run: dry_run,
        queue_proposals: queue_proposals,
        reviewer: current_admin_user.email,
        notes: discovery_params[:notes],
        admin_user: current_admin_user
      )

      notice = if queue_proposals
                 "Discovery started. Proposals will be queued when the run completes."
               else
                 "Discovery started. Refresh the run page in a moment to review absent candidates."
               end
      redirect_to custom_admin_pipeline_run_path(run), notice: notice
    rescue ArgumentError, CompanyDiscoveryService::CostLimitExceededError => e
      redirect_to new_custom_admin_discovery_path, alert: e.message
    end

    private

    def discovery_params
      params.require(:discovery).permit(:discovery_type, :category_id, :category_name, :company_id, :company_name, :year, :country, :funding_year, :limit, :notes)
    end

    def category_value
      return discovery_params[:category_name].presence if discovery_params[:category_id].blank?

      Category.find_by(id: discovery_params[:category_id])&.name
    end

    def web_search_available?
      ENV["OPENAI_API_KEY"].present? && ENV.fetch("DISCOVERY_USE_WEB_SEARCH", "true") == "true"
    end

    def country_options
      Company.where(visible: true).with_resolved_country.distinct.order(:country).pluck(:country)
    end
  end
end
