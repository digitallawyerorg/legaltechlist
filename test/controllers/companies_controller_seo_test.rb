require "test_helper"

class CompaniesControllerTest < ActionController::TestCase
  test "index includes h1 heading" do
    get :index
    assert_response :success
    assert_select "h1.company-index-title", text: "Legal Tech Companies"
  end

  test "index includes meta description" do
    get :index
    assert_response :success
    assert_select "meta[name=?][content]", "description"
  end
end
