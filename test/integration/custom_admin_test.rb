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

  test "company review index is available to signed-in admin users" do
    sign_in admin_users(:one)

    get custom_admin_company_reviews_path

    assert_response :success
    assert_select "h1", "Company Review"
    assert_select "a", "Review"
  end

  test "company review show is available to signed-in admin users" do
    sign_in admin_users(:one)

    get custom_admin_company_review_path(companies(:one))

    assert_response :success
    assert_select "h1", companies(:one).name
    assert_select "h2", "Public Record"
    assert_select "a", "Edit in ActiveAdmin"
  end

  test "pipeline run index and show are available to signed-in admin users" do
    sign_in admin_users(:one)
    run = PipelineRun.create!(name: "Manual verifier", run_type: "company_verification", status: "succeeded", records_processed: 1, details: { "company_id" => companies(:one).id })

    get custom_admin_pipeline_runs_path
    assert_response :success
    assert_select "h1", "Pipeline Runs"
    assert_select "td", "Manual verifier"

    get custom_admin_pipeline_run_path(run)
    assert_response :success
    assert_select "h1", "Manual verifier"
    assert_select "h2", "Raw Details"
  end
end
