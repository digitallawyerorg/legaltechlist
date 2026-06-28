class CompaniesController < ApplicationController
  FEED_COMPANY_LIMIT = 100

  before_action :set_company, only: [:show, :edit, :update, :destroy]

  # GET /companies
  # GET /companies.json

  # this search could easily be made much more complex and powerful
  # with ands and ors if necessary
  def index
    @base_companies = Company.publicly_visible.includes(:category)
    @companies = @base_companies
    @base_company_count = @base_companies.count

    begin
      # Search
      @companies = @companies.text_search(params[:query]) if params[:query].present?

      # Filters
      @companies = @companies.where(category_id: params[:category]) if params[:category].present?
      @companies = @companies.where("location ILIKE ?", "%#{params[:location]}%") if params[:location].present?
      @companies = @companies.where("LOWER(TRIM(status)) = ?", normalized_status_param) if normalized_status_param.present?

      # Sorting
      case params[:sort] || 'founded_desc'
      when 'name_asc'
        @companies = @companies.order(name: :asc)
      when 'name_desc'
        @companies = @companies.order(name: :desc)
      when 'founded_desc'
        @companies = @companies.order(founded_date: :desc)
      when 'founded_asc'
        @companies = @companies.order(founded_date: :asc)
      when 'funding_desc'
        @companies = @companies.order(total_funding_amount_usd: :desc)
      when 'updated_desc'
        @companies = @companies.order(updated_at: :desc)
      end

      @total_count = @companies.count
      @category_counts = category_counts
      @status_counts = status_counts
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

  end

  # GET /companies/new
  def new
    @company = Company.new
  end

  # GET /companies/1/edit
  def edit

  end

  # POST /companies
  # POST /companies.json
  # Actual companies are created in the Admin module. This function will accept
  # the values from the new form, verify them, and then e-mail them to the
  # administrator to be added later.
  def create
    @company = Company.new(company_params)
    @company.visible = false

    respond_to do |format|
      if @company.save
        # set company to invisible

        SuggestionMailer.newcompany_email(@company).deliver_now

        format.html { redirect_to @company, notice: t('controllers.company.created_success') }
        format.json { render :show, status: :created, location: @company }
      else
        format.html { render :new }
        format.json { render json: @company.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /companies/1
  # PATCH/PUT /companies/1.json
  # Actual companies are edited in the Admin module. This function will accept the
  # values from the edit form, verify them, and then e-mail them to the
  # administrator to be added later.
  def update
    respond_to do |format|
      if @company.update(company_params)
        SuggestionMailer.editcompany_email(@company).deliver_now

        format.html { redirect_to @company, notice: t('controllers.company.updated_success') }
        format.json { render :show, status: :ok, location: @company }
      else
        flash.now[:notice] = "Failed, please try again"
        format.html { render :edit }
        format.json { render json: @company.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /companies/1
  # DELETE /companies/1.json
  def destroy
    @company.destroy
    respond_to do |format|
      format.html { redirect_to companies_url, notice: t('controllers.company.destroyed_success') }
      format.json { head :no_content }
    end
  end

  private
    def category_counts
      @base_companies.joins(:category).group("categories.id", "categories.name").order("categories.name ASC").count.map do |(category_id, name), count|
        { id: category_id, name: name, count: count }
      end
    end

    def status_counts
      @base_companies.where.not(status: [nil, ""]).group("LOWER(TRIM(status))").order("LOWER(TRIM(status))").count
    end

    def normalized_status_param
      params[:status].to_s.strip.downcase.presence
    end

    # Use callbacks to share common setup or constraints between actions.
    def set_company
      scope = action_name == "show" ? Company.includes(:category, :secondary_category, :successor_company, :business_model, :business_models, :company_logo, :target_client, :target_clients, :tags) : Company
      @company = scope.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def company_params
      params.require(:company).permit(:name, :location, :founded_date, :category, :secondary_category,
                                      :business_model, :target_client, :description, :main_url,
                                      :twitter_url, :angellist_url, :crunchbase_url, :linkedin_url,
                                      :facebook_url, :legalio_url, :status, :employee_count,
                                      :all_tags, :category_id, :secondary_category_id, :target_client_id,
                                      :business_model_id, :visible, :contact_name, :contact_email,
                                      :codex_presenter, :codex_presentation_date)
    end
end
