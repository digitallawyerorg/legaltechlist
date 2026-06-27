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

  test "index renders dense table and filter sidebar" do
    get :index

    assert_response :success
    assert_select ".company-sidebar-title", "Filter"
    assert_select ".company-filter-link", text: /All categories/
    assert_select "table.company-table"
    assert_select "th", "Company"
    assert_select "th", "Funding"
    assert_select ".company-search input[placeholder='Search companies by name, category, or location']"
    assert_select ".company-pagination-count", text: /Showing \d+-\d+ of \d+ companies/
    assert_select "select[name='sort']"
    assert_select "select[name='sort'] option[selected='selected']", "Recently updated"
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
    assert_select ".company-filter-link.is-active", text: /Active/
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
