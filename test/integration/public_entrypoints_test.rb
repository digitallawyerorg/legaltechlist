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

  test "admin login route is reachable" do
    get new_admin_user_session_path

    assert_response :success
  end
end
