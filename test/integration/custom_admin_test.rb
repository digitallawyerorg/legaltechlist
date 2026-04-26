require "test_helper"

class CustomAdminTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "custom admin redirects unauthenticated users to login" do
    get custom_admin_root_path

    assert_redirected_to new_admin_user_session_path
  end

  test "custom admin dashboard is available to signed-in admin users" do
    sign_in admin_users(:one)

    get custom_admin_root_path

    assert_response :success
    assert_select "h1", "TechIndex Admin"
    assert_select "a", "Open ActiveAdmin"
  end

  test "quality dashboard is available to signed-in admin users" do
    sign_in admin_users(:one)

    get custom_admin_quality_path

    assert_response :success
    assert_select "h1", "Quality Dashboard"
    assert_select "div", text: "Missing URLs"
    assert_select "div", text: "Duplicate-domain candidates"
  end
end
