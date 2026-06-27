require "test_helper"

class PublicEntrypointsTest < ActionDispatch::IntegrationTest
  test "public entry pages respond successfully" do
    get root_path
    assert_response :success

    get companies_path
    assert_response :success

    get statistics_path
    assert_response :success

    get rails_health_check_path
    assert_response :success
  end

  test "home page prioritizes category browsing before statistics" do
    get root_path

    assert_response :success
    assert_select ".home-title", "CodeX TechIndex"
    assert_select ".home-category-card"
    assert_operator @response.body.index(">By category</h2>"), :<, @response.body.index(">Statistics</h2>")
  end

  test "public navbar includes global company search" do
    get root_path

    assert_response :success
    assert_select "form.public-nav-search[action='#{companies_path}'][method='get']"
    assert_select ".public-nav-search input[name='query'][type='search']"
  end

  test "admin login route is reachable" do
    get new_admin_user_session_path

    assert_response :success
  end
end
