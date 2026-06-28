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
    assert_select ".company-sidebar", count: 0
    assert_select "table.company-table"
    assert_select "th", "Company"
    assert_select "th", "HQ"
    refute_includes css_select("th").map(&:text), "Funding"
    assert_select ".company-search input[placeholder='Search by name, category, or location']"
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
    @company.update_columns(location: "San Francisco, CA")
    companies(:two).update_columns(location: "New York, NY")

    get :index, params: { location: "San Francisco" }

    assert_response :success
    assert_includes assigns(:companies), @company
    assert_not_includes assigns(:companies), companies(:two)
    assert_select ".company-filter-btn", text: /San Francisco/
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

  test "should create company" do
    assert_difference('Company.count') do
      post :create, params: {
        company: {
          angellist_url: @company.angellist_url,
          category_id: @company.category_id,
          business_model_id: @company.business_model_id,
          target_client_id: @company.target_client_id,
          crunchbase_url: @company.crunchbase_url,
          description: @company.description,
          employee_count: @company.employee_count,
          founded_date: @company.founded_date,
          location: @company.location,
          main_url: @company.main_url,
          name: @company.name,
          twitter_url: @company.twitter_url
        }
      }
    end

    assert_redirected_to company_path(assigns(:company))
  end

  test "should show company" do
    get :show, params: { id: @company }
    assert_response :success
  end

  test "should get edit" do
    get :edit, params: { id: @company }
    assert_response :success
  end

  test "should update company" do
    patch :update, params: {
      id: @company,
      company: {
        angellist_url: @company.angellist_url,
        category_id: @company.category_id,
        business_model_id: @company.business_model_id,
        target_client_id: @company.target_client_id,
        crunchbase_url: @company.crunchbase_url,
        description: @company.description,
        employee_count: @company.employee_count,
        founded_date: @company.founded_date,
        location: @company.location,
        main_url: @company.main_url,
        name: @company.name,
        twitter_url: @company.twitter_url
      }
    }
    assert_redirected_to company_path(assigns(:company))
  end

  test "public company destroy route is not available" do
    assert_no_difference('Company.count') do
      assert_raises(ActionController::UrlGenerationError) do
        delete :destroy, params: { id: @company }
      end
    end
  end
end
