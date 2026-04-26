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

  test "should destroy company" do
    assert_difference('Company.count', -1) do
      delete :destroy, params: { id: @company }
    end

    assert_redirected_to companies_path
  end
end
