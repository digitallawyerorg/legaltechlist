class CompaniesController < ApplicationController
  include UserSubmissionProtection

  FEED_COMPANY_LIMIT = 100

  before_action :set_company, only: [:show, :suggest_update]

  # GET /companies
  # GET /companies.json

  # this search could easily be made much more complex and powerful
  # with ands and ors if necessary
  def index
    @base_companies = Company.publicly_visible.includes(:category)
    @base_company_count = @base_companies.count

    begin
      @companies = filtered_companies_scope
      @total_count = @companies.count
      @category_counts = category_counts
      @status_counts = status_counts
      @country_counts = country_counts
      @sort_options = [["Newest companies", "founded_desc"], ["Oldest companies", "founded_asc"], ["Company name (A-Z)", "name_asc"], ["Company name (Z-A)", "name_desc"], ["Most funding raised", "funding_desc"]]
      @companies = @companies.page(params[:page]).per(25)
    rescue => e
      Rails.logger.error "Error in companies#index: #{e.message}"
      @companies = Company.none
      flash.now[:error] = "An error occurred while loading companies"
    end
  end

  def search
    @query = params[:q].to_s.strip
    if @query.present?
      results = Company.publicly_visible
                       .includes(:category)
                       .text_search(@query)
                       .order(name: :asc)
                       .limit(10)
                       .select("companies.*, COUNT(*) OVER() AS full_count")
      @companies = results
      @total_count = results.first&.try(:full_count).to_i
    else
      @companies = Company.none
      @total_count = 0
    end
  end

  def map
    @companies = Company.publicly_visible.where.not(latitude: nil).where.not(longitude: nil)
    @hash = Gmaps4rails.build_markers(@companies) do |company, marker|
      marker.lat company.latitude
      marker.lng company.longitude
      contentString = '<div id="content">'+
        '<h2 id="firstHeading" class="firstHeading">' +
        company.name +
        '</h2>'+
        '<div id="bodyContent">'+
        '<p>' +
        company.description +
        '</p>'+
        '(last updated June 22, 2009).</p>'+
        '<a href="/companies/' +
        company.id.to_s +
        '" class="btn btn-default">View Info</a>' +
        '</div>'+
        '</div>';
      marker.infowindow contentString
      marker.json({ title: company.name })
    end
  end

  def feed
    @companies = Company.publicly_visible
                        .includes(:category)
                        .order(created_at: :desc)
                        .limit(FEED_COMPANY_LIMIT)

    respond_to do |format|
      format.rss { render :layout => false }
    end
  end

  # GET /companies/1
  # GET /companies/1.json
  def show
    assign_company_neighbors
  end

  # GET /companies/new
  def new
    @contribution_form = CompanyContributionForm.new
  end

  # POST /companies/1/suggest_update
  def suggest_update
    suggestion = suggest_update_params.to_h.symbolize_keys

    if suggestion[:issue_type].blank? || suggestion[:message].blank?
      redirect_to @company, alert: "Please choose an issue type and describe what should change."
      return
    end

    unless UserSuggestionIssueTypes.valid?(suggestion[:issue_type])
      redirect_to @company, alert: "Please choose a valid issue type."
      return
    end

    if suggestion[:message].to_s.strip.length < UserSubmissionProtection::MIN_SUGGESTION_MESSAGE_LENGTH
      redirect_to @company, alert: "Please provide a bit more detail about the change."
      return
    end

    if suggestion[:submitter_email].blank?
      redirect_to @company, alert: "Please enter your email address."
      return
    end

    UserSuggestionIntakeService.call(company: @company, suggestion: suggestion, request_ip: request.remote_ip)
    record_submission_fingerprint!

    redirect_to @company, notice: "Thank you. Your suggestion has been submitted for review."
  end

  # POST /companies
  # POST /companies.json
  def create
    @contribution_form = CompanyContributionForm.from_params(params)

    respond_to do |format|
      if @contribution_form.valid?
        UserContributionIntakeService.call(form: @contribution_form, request_ip: request.remote_ip)
        record_submission_fingerprint!

        format.html { redirect_to companies_path, notice: "Thank you. Your company suggestion has been submitted for review." }
        format.json { head :created }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @contribution_form.errors, status: :unprocessable_entity }
      end
    end
  end

  private
    NAVIGATION_CONTEXT_KEYS = %i[query country city location sort category status].freeze
    DEFAULT_NAVIGATION_CONTEXT = { sort: "name_asc" }.freeze

    def filtered_companies_scope(source_params = params)
      companies = Company.publicly_visible.includes(:category)

      companies = companies.text_search(source_params[:query]) if source_params[:query].present?
      category_ids = selected_category_ids(source_params)
      companies = companies.where(category_id: category_ids) if category_ids.any?
      companies = companies.where(country: source_params[:country]) if source_params[:country].present?
      companies = companies.where("city ILIKE ?", "%#{source_params[:city]}%") if source_params[:city].present?
      companies = companies.where("location ILIKE ?", "%#{source_params[:location]}%") if source_params[:location].present?
      statuses = selected_statuses(source_params)
      companies = companies.where("LOWER(TRIM(status)) IN (?)", statuses) if statuses.any?

      apply_company_sort(companies, source_params[:sort])
    end

    def apply_company_sort(companies, sort_param)
      case sort_param.presence || "founded_desc"
      when "name_asc"
        companies.order(Arel.sql("companies.name ASC, companies.id ASC"))
      when "name_desc"
        companies.order(Arel.sql("companies.name DESC, companies.id DESC"))
      when "founded_desc"
        companies.order(founded_date: :desc, id: :desc)
      when "founded_asc"
        companies.order(founded_date: :asc, id: :asc)
      when "funding_desc"
        companies.order(total_funding_amount_usd: :desc, id: :desc)
      when "updated_desc"
        companies.order(updated_at: :desc, id: :desc)
      else
        companies.order(founded_date: :desc, id: :desc)
      end
    end

    def companies_navigation_context
      context = params.permit(:query, :country, :city, :location, :sort, category: [], status: [])
                     .to_h
                     .symbolize_keys
                     .slice(*NAVIGATION_CONTEXT_KEYS)
                     .compact_blank
      context.presence || DEFAULT_NAVIGATION_CONTEXT
    end

    def assign_company_neighbors
      @companies_nav_context = companies_navigation_context
      @company_neighbors = company_neighbors_for(@company, @companies_nav_context)

      return if @company_neighbors.values.compact.any?
      return if filtered_companies_scope(@companies_nav_context).exists?(id: @company.id)

      @companies_nav_context = DEFAULT_NAVIGATION_CONTEXT
      @company_neighbors = company_neighbors_for(@company, @companies_nav_context)
    end

    def company_neighbors_for(company, context)
      scope = filtered_companies_scope(context)
      company_rows = scope.pluck(:id, :name)
      index = company_rows.index { |company_id, _name| company_id == company.id }
      return { prev: nil, next: nil } unless index

      count = company_rows.length
      prev_index = index.positive? ? index - 1 : count - 1
      next_index = index < count - 1 ? index + 1 : 0
      prev_id, prev_name = company_rows[prev_index]
      next_id, next_name = company_rows[next_index]

      {
        prev: { id: prev_id, name: prev_name },
        next: { id: next_id, name: next_name }
      }
    end

    def category_counts
      @base_companies.joins(:category).group("categories.id", "categories.name").order("categories.name ASC").count.map do |(category_id, name), count|
        { id: category_id, name: name, count: count }
      end
    end

    def status_counts
      @base_companies.where.not(status: [nil, ""]).group("LOWER(TRIM(status))").order("LOWER(TRIM(status))").count
    end

    def country_counts
      @base_companies.with_resolved_country.group(:country).order(:country).count
    end

    def selected_category_ids(source_params = params)
      Array(source_params[:category]).map(&:presence).compact.map(&:to_i)
    end

    def selected_statuses(source_params = params)
      Array(source_params[:status]).map { |status| status.to_s.strip.downcase }.reject(&:blank?)
    end

    def set_company
      scope = action_name == "show" ? Company.includes(:category, :secondary_category, :successor_company, :business_model, :business_models, :company_logo, :target_client, :target_clients, :tags) : Company
      @company = scope.find(params[:id])
    end

    def suggest_update_params
      params.permit(:issue_type, :message, :source_url, :submitter_email)
    end
end
