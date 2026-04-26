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
    assert_select "a", "Manage Companies"
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
    assert_select "a", "Edit Company"
    assert_select "button", "Run Agent Review"
  end

  test "company agent review action requires authentication" do
    post custom_admin_company_agent_review_path(companies(:one))

    assert_redirected_to new_admin_user_session_path
  end

  test "company agent review action creates review output without changing company" do
    sign_in admin_users(:one)
    company = companies(:one)
    original_attributes = company.attributes.slice("name", "description", "main_url", "visible", "quality_status", "verification_verdict", "quality_score", "canonical_domain", "fingerprint", "updated_at")

    assert_difference "PipelineRun.count", 1 do
      post custom_admin_company_agent_review_path(company)
    end

    run = PipelineRun.order(:created_at).last
    assert_redirected_to custom_admin_agent_review_path(run)
    assert_equal "company_agent_review", run.run_type
    assert_equal "agent_proposal_no_public_writes", run.details["mode"]
    assert_equal company.id, run.details["company_id"]
    assert_equal original_attributes, company.reload.attributes.slice("name", "description", "main_url", "visible", "quality_status", "verification_verdict", "quality_score", "canonical_domain", "fingerprint", "updated_at")
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

  test "agent review pages show evidence and proposed corrections without writes" do
    sign_in admin_users(:one)
    run = PipelineRun.create!(name: "Agent review sample", run_type: "company_review", status: "succeeded", agent_name: "CompanyVerifierAgent", records_processed: 1, details: { "company_id" => companies(:one).id, "evidence" => [{ "title" => "Company website", "url" => "https://example.com", "summary" => "Public website confirms the company exists." }], "proposed_corrections" => { "description" => "Neutral proposed description." }, "risks" => ["Needs human verification"] })

    get custom_admin_agent_reviews_path
    assert_response :success
    assert_select "h1", "Agent Reviews"
    assert_select "td", "Agent review sample"

    get custom_admin_agent_review_path(run)
    assert_response :success
    assert_select "h1", "Agent review sample"
    assert_select "h2", "Evidence"
    assert_select "h2", "Proposed Corrections"
    assert_equal companies(:one).description, companies(:one).reload.description
  end

  test "custom resource pages support taxonomy CRUD" do
    sign_in admin_users(:one)

    get custom_admin_resources_path(resource: "categories")
    assert_response :success
    assert_select "h1", "Categories"

    post custom_admin_resources_path(resource: "categories"), params: { category: { name: "New Category", description: "Review taxonomy" } }
    assert_redirected_to custom_admin_resources_path(resource: "categories")
    category = Category.find_by!(name: "New Category")

    patch custom_admin_resource_record_path(resource: "categories", id: category.id), params: { category: { name: "Updated Category", description: "Updated taxonomy" } }
    assert_redirected_to custom_admin_resources_path(resource: "categories")
    assert_equal "Updated Category", category.reload.name
  end

  test "custom company management supports edit and export" do
    sign_in admin_users(:one)
    company = companies(:one)

    get custom_admin_companies_path
    assert_response :success
    assert_select "h1", "Companies"

    get edit_custom_admin_company_path(company)
    assert_response :success
    assert_select "h1", "Edit #{company.name}"

    patch custom_admin_company_path(company), params: { company: { name: "Custom Managed Company", description: company.description, main_url: company.main_url, visible: company.visible, category_id: company.category_id, business_model_id: company.business_model_id, target_client_id: company.target_client_id, sub_category_id: company.sub_category_id } }
    assert_redirected_to custom_admin_company_review_path(company)
    assert_equal "Custom Managed Company", company.reload.name

    get export_custom_admin_companies_csv_path
    assert_response :success
    assert_includes response.media_type, "text/csv"
  end
end
