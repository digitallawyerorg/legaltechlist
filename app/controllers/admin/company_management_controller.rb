require "csv"

module Admin
  class CompanyManagementController < BaseController
    REVIEW_SIGNALS = {
      "missing_url" => "Missing URL",
      "weak_description" => "Weak description",
      "description_review" => "Description review",
      "duplicate_name" => "Duplicate name",
      "duplicate_domain" => "Duplicate domain",
      "needs_review" => "Needs review",
      "rejected" => "Rejected",
      "unknown_taxonomy" => "Unknown taxonomy"
    }.freeze

    UPDATED_SINCE_OPTIONS = {
      "7" => "Last 7 days",
      "30" => "Last 30 days",
      "90" => "Last 90 days"
    }.freeze

    def index
      @filters = company_filter_params
      @categories = Category.order(:name)
      @business_models = BusinessModel.canonical.order(:name)
      @target_clients = TargetClient.canonical.order(:name)
      @quality_statuses = Company.where.not(quality_status: [nil, ""]).distinct.order(:quality_status).pluck(:quality_status)
      @review_signal_options = REVIEW_SIGNALS
      @updated_since_options = UPDATED_SINCE_OPTIONS
      metrics = AdminDashboardMetrics.load
      @duplicate_domain_company_ids = metrics[:duplicate_domain_ids].to_set
      @duplicate_name_company_ids = metrics[:duplicate_name_ids].to_set
      @company_summary_counts = metrics[:company_summary_counts]
      @active_filter_count = active_filter_count
      @companies = filtered_companies.page(params[:page]).per(25)
    end

    def new
      @company = Company.new(visible: false)
    end

    def fill_from_url
      name = params.dig(:company, :name).to_s.strip
      url = params.dig(:company, :main_url).to_s.strip

      if name.blank? || url.blank?
        redirect_to new_custom_admin_company_path, alert: "Company name and website URL are required to fill from URL."
        return
      end

      result = AdminManualEntryProposalService.call(name: name, url: url, admin_user: current_admin_user)
      warning = helpers.admin_duplicate_match_warning(result[:candidate])
      flash[:warning] = warning if warning.present?

      redirect_to edit_custom_admin_company_proposal_path(result[:proposal]), notice: "Proposal created and enriched from URL. Review the draft before approving."
    rescue StandardError => e
      redirect_to new_custom_admin_company_path, alert: "Could not fill from URL: #{e.message}"
    end

    def create
      @company = Company.new(company_params)
      @company.skip_geocoding = true
      set_identity_fields(@company)

      if @company.save
        redirect_to custom_admin_company_review_path(@company), notice: "Company created for review."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @company = Company.find(params[:id])
    end

    def update
      @company = Company.find(params[:id])
      @company.assign_attributes(company_params)
      @company.skip_geocoding = true
      set_identity_fields(@company)

      if @company.save
        redirect_to custom_admin_company_review_path(@company), notice: "Company updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      company = Company.find(params[:id])
      company_name = company.name

      Company.transaction do
        CompanyProposal.where(company_id: company.id).update_all(company_id: nil, updated_at: Time.current)
        company.destroy!
      end

      redirect_to custom_admin_companies_path, notice: "#{company_name} was deleted."
    rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey => e
      redirect_to custom_admin_company_review_path(company), alert: "Could not delete #{company_name}: #{e.message}"
    end

    def upload
    end

    def import
      stats = ImportCsvToCompanyService.import(params.require(:dump).require(:file))
      redirect_to custom_admin_companies_path, notice: "CSV imported. Created: #{stats[:created]}, Updated: #{stats[:updated]}, Skipped: #{stats[:skipped]}, Errors: #{stats[:errors]}."
    end

    def review_import_candidates
      run = CompanyCandidateImportService.call(file: params.require(:dump).require(:file), admin_user: current_admin_user, notes: "Triggered from custom CSV candidate import automation")
      automation = run.details["automation"] || {}

      redirect_to custom_admin_company_proposals_path, notice: "Candidate import processed. Auto-drafted: #{automation['auto_drafted'].to_i}. Needs review: #{automation['needs_review'].to_i}. Duplicate review: #{automation['needs_duplicate_review'].to_i}."
    end

    def export
      csv = CSV.generate(encoding: Encoding::UTF_8.name) { |rows| ImportCsvToCompanyService.export(rows) }
      send_data csv, type: "text/csv; charset=utf-8; header=present", disposition: "attachment; filename=companies.csv"
    end

    private

    def company_filter_params
      params.permit(:q, :visibility, :category_id, :business_model_id, :target_client_id, :quality_status, :review_signal, :updated_since)
    end

    def filtered_companies
      scope = Company.includes(:category, :business_model, :target_client).order(updated_at: :desc)
      scope = scope.text_search(@filters[:q]) if @filters[:q].present?
      scope = scope.where(visible: @filters[:visibility] == "visible") if @filters[:visibility].in?(%w[visible hidden])
      scope = scope.where(category_id: @filters[:category_id]) if @filters[:category_id].present?
      scope = scope.where(business_model_id: @filters[:business_model_id]) if @filters[:business_model_id].present?
      scope = scope.where(target_client_id: @filters[:target_client_id]) if @filters[:target_client_id].present?
      scope = scope.where(quality_status: @filters[:quality_status]) if @filters[:quality_status].present?
      scope = apply_review_signal(scope)
      scope = scope.where(updated_at: @filters[:updated_since].to_i.days.ago..) if @filters[:updated_since].in?(UPDATED_SINCE_OPTIONS.keys)
      scope
    end

    def apply_review_signal(scope)
      case @filters[:review_signal]
      when "missing_url" then scope.missing_main_url
      when "weak_description" then scope.weak_description
      when "description_review" then scope.description_review_candidates
      when "duplicate_name" then scope.duplicate_name_candidates
      when "duplicate_domain" then scope.duplicate_domain_candidates
      when "needs_review" then scope.needs_review
      when "rejected" then scope.rejected_quality
      when "unknown_taxonomy" then scope.left_joins(:category, :business_model, :target_client).where("categories.id IS NULL OR categories.name = :unknown OR business_models.id IS NULL OR business_models.name = :unknown OR target_clients.id IS NULL OR target_clients.name = :unknown", unknown: "Unknown")
      else scope
      end
    end

    def active_filter_count
      @filters.to_h.except("controller", "action").values.count(&:present?)
    end

    def company_params
      params.require(:company).permit(:name, :location, :country, :city, :founded_date, :description, :main_url, :twitter_url, :crunchbase_url, :linkedin_url, :facebook_url, :legalio_url, :legaltech_atlas_url, :status, :category_id, :secondary_category_id, :successor_company_id, :target_client_id, :business_model_id, :visible, :contact_email, :contact_name, :codex_presenter, :codex_presentation_date, :logo_url, :total_funding_amount_usd, :funding_status, :number_of_funding_rounds, :exit_date, :founders, :headquarters_region, :quality_status, :verification_verdict, :quality_score, :verified_at, :enriched_at, :quality_reviewed_at, :human_reviewed_at, :source, :source_url, :all_tags, business_model_ids: [], target_client_ids: [])
    end

    def set_identity_fields(company)
      company.canonical_domain = company.canonical_main_domain
      company.fingerprint = company.calculated_fingerprint
    end
  end
end
