require "csv"

module Admin
  class CompanyManagementController < BaseController
    def index
      @companies = Company.includes(:category, :business_model, :target_client).order(updated_at: :desc).page(params[:page]).per(25)
    end

    def new
      @company = Company.new(visible: false)
    end

    def create
      @company = Company.new(company_params)
      set_identity_fields(@company)

      if @company.save
        redirect_to custom_admin_company_reviews_path, notice: "Company created for review."
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
      set_identity_fields(@company)

      if @company.save
        redirect_to custom_admin_company_review_path(@company), notice: "Company updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def upload
    end

    def import
      stats = ImportCsvToCompanyService.import(params.require(:dump).require(:file))
      redirect_to custom_admin_companies_path, notice: "CSV imported. Created: #{stats[:created]}, Updated: #{stats[:updated]}, Skipped: #{stats[:skipped]}, Errors: #{stats[:errors]}."
    end

    def review_import_candidates
      run = AtlasCandidateImportReviewService.call(file: params.require(:dump).require(:file), reviewer: current_admin_user.email, notes: "Triggered from custom CSV candidate review")

      redirect_to custom_admin_pipeline_run_path(run), notice: "Candidate import review created. No company records were changed."
    end

    def export
      csv = CSV.generate(encoding: Encoding::UTF_8.name) { |rows| ImportCsvToCompanyService.export(rows) }
      send_data csv, type: "text/csv; charset=utf-8; header=present", disposition: "attachment; filename=companies.csv"
    end

    private

    def company_params
      params.require(:company).permit(:name, :location, :founded_date, :description, :main_url, :twitter_url, :angellist_url, :crunchbase_url, :linkedin_url, :facebook_url, :legalio_url, :status, :employee_count, :category_id, :target_client_id, :business_model_id, :sub_category_id, :visible, :contact_email, :contact_name, :codex_presenter, :codex_presentation_date, :logo_url, :total_funding_amount_usd, :funding_status, :number_of_funding_rounds, :exit_date, :founders, :headquarters_region, :quality_status, :verification_verdict, :quality_score, :verified_at, :enriched_at, :quality_reviewed_at, :human_reviewed_at, :source, :source_url, :all_tags)
    end

    def set_identity_fields(company)
      company.canonical_domain = company.canonical_main_domain
      company.fingerprint = company.calculated_fingerprint
    end
  end
end
