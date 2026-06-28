require 'test_helper'

class CompaniesControllerTest < ActionController::TestCase
  setup do
    @company = companies(:one)
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:companies)
  end

  test "index renders dense table and horizontal filter bar" do
    get :index

    assert_response :success
    assert_select ".company-filter-bar"
    assert_select ".company-filter-btn", minimum: 2
    assert_select ".company-filter-checkbox-form", minimum: 1
    assert_select "input[name='category[]'][type='checkbox']", minimum: 1
    assert_select "input[name='category[]'][type='checkbox'][checked='checked']", minimum: 1
    assert_select ".company-sidebar", count: 0
    assert_select "table.company-table"
    assert_select "th", "Company"
    assert_select "th", "HQ"
    refute_includes css_select("th").map(&:text), "Funding"
    assert_select ".company-search input[placeholder='Search companies']"
    assert_select ".company-filter-master input[data-company-filter-master='category']"
    assert_select ".company-filter-master .company-filter-checkbox-label", text: "All categories"
    assert_select "[data-company-filter-select-all]", count: 0
    assert_select "[data-company-filter-clear]", count: 0
    assert_select ".company-pagination-count", text: /Showing \d+-\d+ of \d+ companies/
    assert_select "select[name='sort']"
    assert_select "select[name='sort'] option[selected='selected']", "Newest companies"
    assert_select "option", text: "Recently updated", count: 0
    assert_select "option", "Company name (A-Z)"
    assert_select "option", "Most funding raised"
  end

  test "index only includes publicly visible companies" do
    hidden = @company.dup
    hidden.name = "Hidden Company"
    hidden.visible = false
    hidden.save!

    get :index

    assert_response :success
    assert_includes assigns(:companies), @company
    assert_not_includes assigns(:companies), hidden
  end

  test "index shows all checkboxes checked when no filter is active" do
    get :index

    assert_response :success
    assert_equal assigns(:base_company_count), assigns(:total_count)
    assert_select "input[name='category[]'][type='checkbox']:not([checked])", count: 0
    assert_select "input[name='status[]'][type='checkbox']:not([checked])", count: 0
    assert_select ".company-filter-btn-active", count: 0
  end

  test "index filters by public status" do
    @company.update_columns(status: "active")
    companies(:two).update_columns(status: "acquired")

    get :index, params: { status: "active" }

    assert_response :success
    assert_includes assigns(:companies), @company
    assert_not_includes assigns(:companies), companies(:two)
    assert_select ".company-filter-btn-active", text: /Active/
    assert_select "input[name='status[]'][value='active'][checked='checked']"
  end

  test "index filters by category" do
    get :index, params: { category: @company.category_id }

    assert_response :success
    assert_includes assigns(:companies), @company
    assert assigns(:companies).all? { |company| company.category_id == @company.category_id }
    assert_select ".company-filter-btn-active", text: /#{Regexp.escape(@company.category.name)}/
    assert_select "input[name='category[]'][value='#{@company.category_id}'][checked='checked']"
  end

  test "index filters by multiple categories with or logic" do
    get :index, params: { category: [@company.category_id, companies(:two).category_id] }

    assert_response :success
    assert_includes assigns(:companies), @company
    assert_includes assigns(:companies), companies(:two)
    assert_select ".company-filter-btn-active", text: /2 categories/
  end

  test "index filters by multiple statuses with or logic" do
    @company.update_columns(status: "active")
    companies(:two).update_columns(status: "acquired")

    get :index, params: { status: %w[active acquired] }

    assert_response :success
    assert_includes assigns(:companies), @company
    assert_includes assigns(:companies), companies(:two)
    assert_select ".company-filter-btn-active", text: /2 statuses/
  end

  test "index filters by location" do
    @company.update_columns(location: "San Francisco, CA", country: "United States", city: "San Francisco")
    companies(:two).update_columns(location: "New York, NY", country: "United States", city: "New York")

    get :index, params: { country: "United States", city: "San Francisco" }

    assert_response :success
    assert_includes assigns(:companies), @company
    assert_not_includes assigns(:companies), companies(:two)
    assert_select ".company-filter-btn-active", text: /San Francisco/
  end

  test "index shows reset link when filters are active" do
    get :index, params: { category: @company.category_id, status: "active" }

    assert_response :success
    assert_select ".company-filter-reset", text: "Reset"
  end

  test "index combines status facet variants case-insensitively" do
    @company.update_columns(status: "active")
    companies(:two).update_columns(status: "Active")

    get :index, params: { status: "active" }

    assert_response :success
    assert_includes assigns(:companies), @company
    assert_includes assigns(:companies), companies(:two)
    assert_equal 2, assigns(:status_counts)["active"]
    assert_equal ["active"], assigns(:status_counts).keys
  end

  test "deep public pagination is rate limited" do
    get :index, params: { page: 21, tag: "corporate law" }

    assert_response :too_many_requests
  end

  test "rss feed is limited to recent visible companies" do
    hidden = @company.dup
    hidden.name = "Hidden Feed Company"
    hidden.visible = false
    hidden.save!

    get :feed, format: :rss

    assert_response :success
    assert_operator assigns(:companies).length, :<=, CompaniesController::FEED_COMPANY_LIMIT
    assert_includes assigns(:companies), @company if @company.visible?
    assert_not_includes assigns(:companies), hidden
  end

  test "search returns matching visible companies as json" do
    get :search, params: { q: @company.name }, format: :json

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal @company.name, payload["companies"].first["name"]
    assert payload["total_count"] >= 1
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "new shows canonical revenue model, target client, and tag checkboxes only" do
    compound_target_client = TargetClient.create!(name: "Corporate Legal, Law Firms", description: "Legacy compound")
    compound_revenue_model = BusinessModel.create!(name: "Subscription, Services", description: "Legacy compound")
    non_discoverable_tag = Tag.create!(name: "saas")

    get :new

    assert_response :success
    checkbox_labels = css_select("label.form-check-label").map(&:text)
    refute_includes checkbox_labels, compound_target_client.name
    refute_includes checkbox_labels, compound_revenue_model.name
    refute_includes checkbox_labels, non_discoverable_tag.name
    refute checkbox_labels.any? { |label| label.include?(",") }, "expected no combinatorial checkbox labels"
    assert_includes checkbox_labels, business_models(:one).name
    assert_includes checkbox_labels, business_models(:two).name
    assert_includes checkbox_labels, target_clients(:one).name
    assert_includes checkbox_labels, target_clients(:two).name
    assert_includes checkbox_labels, "artificial intelligence"
    assert_equal BusinessModel.canonical.order(:name).pluck(:name), checkbox_labels & BusinessModel.canonical.pluck(:name)
    assert_equal TargetClient.canonical.order(:name).pluck(:name), checkbox_labels & TargetClient.canonical.pluck(:name)
    assert_equal Tag.discoverable.pluck(:name), checkbox_labels & Tag.discoverable.pluck(:name)
  end

  test "new form omits deprecated AngelList field" do
    get :new

    assert_response :success
    assert_select "input[name='company_contribution[angellist_url]']", count: 0
  end

  test "rejects contribution without contact name" do
    assert_no_difference("CompanyProposal.count") do
      post :create, params: { company_contribution: contribution_params.except(:contact_name) }
    end

    assert_response :unprocessable_entity
    assert_select ".company-suggest-errors"
  end

  test "should create proposal from contribution form" do
    assert_no_difference('Company.count') do
      assert_difference('CompanyProposal.count', 1) do
        post :create, params: { company_contribution: contribution_params }
      end
    end

    assert_redirected_to companies_path
    proposal = CompanyProposal.order(:id).last
    assert_equal "user_contribution", proposal.proposal_type
    assert_equal "contributor@example.com", proposal.submitter_email
  end

  def contribution_params
    {
      contact_email: "contributor@example.com",
      contact_name: "Ada Contributor",
      name: "Suggested Legal Co",
      main_url: "https://suggested-legal.example",
      location: "Stanford, CA",
      founded_date: "2023",
      category_id: @company.category_id,
      description: "A long enough description for a suggested legal technology company.",
      status: "active",
      business_model_ids: [@company.business_model_id],
      target_client_ids: [@company.target_client_id],
      tag_names: ["artificial intelligence"]
    }
  end

  test "should show company" do
    get :show, params: { id: @company }
    assert_response :success
  end

  test "show renders prev and next navigation in default name order" do
    get :show, params: { id: companies(:two) }

    assert_response :success
    assert_select "nav.company-show-nav"
    assert_select "nav.company-show-nav a.company-show-nav-prev", text: /#{Regexp.escape(companies(:one).name)}/
    assert_select "nav.company-show-nav a.company-show-nav-next[href=?]", company_path(companies(:one), sort: "name_asc")
  end

  test "show next link uses default name order for direct visits" do
    get :show, params: { id: @company }

    assert_response :success
    assert_select "nav.company-show-nav a.company-show-nav-next[href=?]", company_path(companies(:two), sort: "name_asc")
    assert_select "nav.company-show-nav a.company-show-nav-prev[href=?]", company_path(companies(:two), sort: "name_asc")
  end

  test "show prev and next wrap within active category filter" do
    get :show, params: { id: companies(:two), category: [companies(:two).category_id], sort: "name_asc" }

    assert_response :success
    assert_select "nav.company-show-nav a.company-show-nav-prev[href=?]", company_path(companies(:two), sort: "name_asc", category: [companies(:two).category_id])
    assert_select "nav.company-show-nav a.company-show-nav-next[href=?]", company_path(companies(:two), sort: "name_asc", category: [companies(:two).category_id])
  end

  test "show falls back to default name order when company is outside filter context" do
    get :show, params: { id: companies(:two), category: [@company.category_id], sort: "name_asc" }

    assert_response :success
    assert_select "nav.company-show-nav a.company-show-nav-prev[href=?]", company_path(companies(:one), sort: "name_asc")
  end

  test "show preserves filter context in neighbor links" do
    get :show, params: { id: @company, sort: "founded_desc" }

    assert_response :success
    assert_select "nav.company-show-nav a.company-show-nav-prev[href=?]", company_path(companies(:two), sort: "founded_desc")
    assert_select "nav.company-show-nav a.company-show-nav-next[href=?]", company_path(companies(:two), sort: "founded_desc")
  end

  test "show with text search query resolves neighbor navigation without ambiguous sql" do
    get :show, params: { id: @company, query: @company.name, sort: "founded_desc" }

    assert_response :success
    assert_select "nav.company-show-nav"
  end

  test "show omits visit website button and renders external link after url" do
    get :show, params: { id: @company }

    assert_response :success
    assert_select ".company-visit-btn", count: 0
    assert_select ".company-hero-website[href=?]", @company.main_url
    assert_select ".company-hero-website .fa-arrow-up-right-from-square"
    assert_select ".company-hero-website .fa-globe", count: 0
    assert_select ".company-hero", count: 1
  end

  test "show renders inactive company url without link and disables reference links" do
    @company.update_columns(status: "inactive")

    get :show, params: { id: @company }

    assert_response :success
    assert_select ".company-hero-website-inactive[title=?]", CompaniesHelper::INACTIVE_COMPANY_TOOLTIP
    assert_select ".company-hero-website[href]", count: 0
    assert_select ".company-source-row-inactive", minimum: 1
    assert_select "a.company-source-row", count: 0
    assert_select ".company-source-inactive-dot", minimum: 1
  end

  test "index company links include list context for show navigation" do
    get :index, params: { sort: "name_asc", category: @company.category_id }

    assert_response :success
    assert_select "a.company-name-link[href=?]", company_path(@company, sort: "name_asc", category: [@company.category_id])
  end

  test "show renders suggest an update button and modal" do
    get :show, params: { id: @company }

    assert_response :success
    assert_select "button.company-suggest-update-btn[data-suggest-update-open]", text: /Suggest an update/
    assert_select "#company-suggest-update-modal"
    assert_select ".company-suggest-update-modal-option", minimum: 7
    assert_select "form[action=?][method=?]", suggest_update_company_path(@company), "post"
    assert_select "#company_suggest_update_message[required]"
    assert_select "#company_suggest_update_submitter_email[required]"
    assert_select "label[for=?] abbr.required-asterisk", "company_suggest_update_message"
    assert_select "label[for=?] abbr.required-asterisk", "company_suggest_update_submitter_email"
  end

  test "suggest update creates proposal and redirects with notice" do
    assert_no_difference -> { ActionMailer::Base.deliveries.size } do
      assert_difference "CompanyProposal.count", 1 do
        post :suggest_update, params: {
          id: @company,
          issue_type: "incorrect_details",
          message: "Founded year should be 2014.",
          source_url: "https://example.com/about",
          submitter_email: "reviewer@example.com"
        }
      end
    end

    assert_redirected_to company_path(@company)
    assert_equal "Thank you. Your suggestion has been submitted for review.", flash[:notice]
    proposal = CompanyProposal.order(:id).last
    assert_equal "user_suggestion", proposal.proposal_type
    assert_equal "incorrect_details", proposal.issue_type
  end

  test "suggest update requires issue type and message" do
    assert_no_difference -> { ActionMailer::Base.deliveries.size } do
      post :suggest_update, params: { id: @company, issue_type: "", message: "" }
    end

    assert_redirected_to company_path(@company)
    assert_match(/issue type/i, flash[:alert].to_s)
  end

  test "suggest update requires submitter email" do
    assert_no_difference -> { ActionMailer::Base.deliveries.size } do
      post :suggest_update, params: {
        id: @company,
        issue_type: "incorrect_details",
        message: "Founded year should be 2014.",
        submitter_email: ""
      }
    end

    assert_redirected_to company_path(@company)
    assert_match(/email/i, flash[:alert].to_s)
  end

  test "honeypot silently accepts bot submissions without creating proposals" do
    assert_no_difference "CompanyProposal.count" do
      post :create, params: { website_url: "http://bot.example", company_contribution: contribution_params }
    end

    assert_redirected_to companies_path
  end

  test "public edit route is not available" do
    assert_raises(ActionController::UrlGenerationError) do
      get :edit, params: { id: @company }
    end
  end

  test "public update route is not available" do
    assert_raises(ActionController::UrlGenerationError) do
      patch :update, params: { id: @company, company_contribution: contribution_params }
    end
  end

  test "public company destroy route is not available" do
    assert_no_difference('Company.count') do
      assert_raises(ActionController::UrlGenerationError) do
        delete :destroy, params: { id: @company }
      end
    end
  end
end
