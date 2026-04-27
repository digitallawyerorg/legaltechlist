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
    assert_select "button", "Run Next Description Review"
    assert_select "button", "Run Next Duplicate Review"
    assert_select "a", /Description review/
    assert_select "a", "Review"
  end

  test "description review queue is available to signed-in admin users" do
    sign_in admin_users(:one)
    company = companies(:one)
    company.update_columns(description: "Short")

    get custom_admin_company_reviews_path(queue: "description_review")

    assert_response :success
    assert_select "h2", "Description review"
    assert_select "td", text: /#{Regexp.escape(company.name)}/
  end

  test "company review show is available to signed-in admin users" do
    sign_in admin_users(:one)

    get custom_admin_company_review_path(companies(:one))

    assert_response :success
    assert_select "h1", companies(:one).name
    assert_select "h2", "Public Record"
    assert_select "a", "Edit Company"
    assert_select "button", "Run Agent Review"
    assert_select "button", "Run Duplicate Review"
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

  test "next description review action requires authentication" do
    post custom_admin_next_description_review_path

    assert_redirected_to new_admin_user_session_path
  end

  test "next description review action creates review output without changing company" do
    sign_in admin_users(:one)
    company = companies(:one)
    company.update_columns(description: "Short", updated_at: 1.day.ago)
    original_attributes = company.reload.attributes.slice("name", "description", "main_url", "visible", "quality_status", "verification_verdict", "quality_score", "canonical_domain", "fingerprint", "updated_at")

    assert_difference "PipelineRun.count", 1 do
      post custom_admin_next_description_review_path
    end

    run = PipelineRun.order(:created_at).last
    assert_redirected_to custom_admin_agent_review_path(run)
    assert_equal "company_agent_review", run.run_type
    assert_equal company.id, run.details["company_id"]
    assert_equal "Triggered from next description review queue", run.details["notes"]
    assert_equal original_attributes, company.reload.attributes.slice("name", "description", "main_url", "visible", "quality_status", "verification_verdict", "quality_score", "canonical_domain", "fingerprint", "updated_at")
  end

  test "next duplicate-domain review action requires authentication" do
    post custom_admin_next_duplicate_domain_review_path

    assert_redirected_to new_admin_user_session_path
  end

  test "next duplicate-domain review action creates review output without changing companies" do
    sign_in admin_users(:one)
    company = companies(:one)
    candidate = companies(:two)
    company.update_columns(main_url: "https://duplicate.example.com", canonical_domain: nil, updated_at: 2.days.ago)
    candidate.update_columns(main_url: "https://www.duplicate.example.com", canonical_domain: nil, updated_at: 1.day.ago)
    original_attributes = company.reload.attributes.slice("name", "description", "main_url", "visible", "quality_status", "verification_verdict", "quality_score", "canonical_domain", "fingerprint", "updated_at")
    original_candidate_attributes = candidate.reload.attributes.slice("name", "description", "main_url", "visible", "quality_status", "verification_verdict", "quality_score", "canonical_domain", "fingerprint", "updated_at")

    assert_difference "PipelineRun.count", 1 do
      post custom_admin_next_duplicate_domain_review_path
    end

    run = PipelineRun.order(:created_at).last
    assert_redirected_to custom_admin_agent_review_path(run)
    assert_equal "duplicate_domain_review", run.run_type
    assert_equal company.id, run.details["company_id"]
    assert_includes run.details["candidate_company_ids"], candidate.id
    assert_equal "Triggered from next duplicate-domain review queue", run.details["notes"]
    assert_equal original_attributes, company.reload.attributes.slice("name", "description", "main_url", "visible", "quality_status", "verification_verdict", "quality_score", "canonical_domain", "fingerprint", "updated_at")
    assert_equal original_candidate_attributes, candidate.reload.attributes.slice("name", "description", "main_url", "visible", "quality_status", "verification_verdict", "quality_score", "canonical_domain", "fingerprint", "updated_at")
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
    run = PipelineRun.create!(name: "Agent review sample", run_type: "company_review", status: "succeeded", agent_name: "CompanyVerifierAgent", records_processed: 1, details: { "company_id" => companies(:one).id, "evidence" => [{ "title" => "Company website", "url" => "https://example.com", "summary" => "Public website confirms the company exists." }], "description_draft" => { "proposed_description" => "ExampleCo provides legal technology software for law firms.", "mode" => "deterministic_fallback" }, "description_critic" => { "verdict" => "revise", "issues" => ["Needs stronger evidence."], "rationale" => "The draft needs more support.", "suggested_revision" => "ExampleCo provides legal technology software for law firms.", "mode" => "deterministic_fallback" }, "review_coordinator" => { "status" => "needs_description_revision", "reasons" => ["Critic requires revision."], "disagreements" => ["Draft passed initial checks but critic requested revision."], "recommended_actions" => ["Revise the description before approving."], "mode" => "deterministic_fallback" }, "duplicate_review" => { "overall_recommendation" => "related_entities", "rationale" => "Records share a domain but need human review.", "pair_reviews" => [{ "candidate_company_id" => companies(:two).id, "relationship" => "related", "confidence" => "low", "reasons" => ["Canonical domains match."] }], "unresolved_questions" => ["Confirm whether these are product or company records."], "mode" => "deterministic_fallback" }, "proposed_corrections" => { "proposed_description" => "ExampleCo provides legal technology software for law firms.", "description_critic_verdict" => "revise", "coordinator_status" => "needs_description_revision" }, "risks" => ["Needs human verification"] })

    get custom_admin_agent_reviews_path
    assert_response :success
    assert_select "h1", "Agent Reviews"
    assert_select "td", "Agent review sample"

    get custom_admin_agent_review_path(run)
    assert_response :success
    assert_select "h1", "Agent review sample"
    assert_select "h2", "Description Draft"
    assert_select "span", "Review only"
    assert_select "p", text: "ExampleCo provides legal technology software for law firms."
    assert_select "h2", "Review Coordinator"
    assert_select "li", "Critic requires revision."
    assert_select "h2", "Description Critic"
    assert_select "li", "Needs stronger evidence."
    assert_select "h2", "Duplicate Review"
    assert_select "td", "Related"
    assert_select "h2", "Evidence"
    assert_select "h2", "Proposed Corrections"
    assert_equal companies(:one).description, companies(:one).reload.description
  end

  test "agent review apply requires authentication" do
    run = PipelineRun.create!(name: "Agent review sample", run_type: "company_review", status: "succeeded", records_processed: 1, details: { "company_id" => companies(:one).id, "proposed_corrections" => { "quality_status" => "needs_review" } })

    post apply_custom_admin_agent_review_path(run), params: { fields: ["quality_status"] }

    assert_redirected_to new_admin_user_session_path
  end

  test "agent review apply updates only selected safe fields and never description" do
    sign_in admin_users(:one)
    company = companies(:one)
    original_description = company.description
    run = PipelineRun.create!(name: "Agent review sample", run_type: "company_review", status: "succeeded", records_processed: 1, details: { "company_id" => company.id, "proposed_corrections" => { "quality_status" => "needs_review", "verification_verdict" => "needs_human_review", "quality_score" => 60, "proposed_description" => "Do not auto-apply this description." } })

    post apply_custom_admin_agent_review_path(run), params: { fields: ["quality_status", "quality_score", "proposed_description"] }

    assert_redirected_to custom_admin_agent_review_path(run)
    company.reload
    run.reload
    assert_equal "needs_review", company.quality_status
    assert_equal 60, company.quality_score
    assert_nil company.verification_verdict
    assert_equal original_description, company.description
    assert_equal "applied", run.details["admin_decision"]["decision"]
    assert_equal({ "quality_status" => "needs_review", "quality_score" => 60 }, run.details["admin_decision"]["applied_changes"])
  end

  test "agent review reject and follow up record decisions without mutating company" do
    sign_in admin_users(:one)
    company = companies(:one)
    original_attributes = company.attributes.slice("quality_status", "verification_verdict", "quality_score", "description")
    rejected_run = PipelineRun.create!(name: "Rejectable review", run_type: "company_review", status: "succeeded", records_processed: 1, details: { "company_id" => company.id, "proposed_corrections" => { "quality_status" => "needs_review" } })
    follow_up_run = PipelineRun.create!(name: "Follow-up review", run_type: "company_review", status: "succeeded", records_processed: 1, details: { "company_id" => company.id, "proposed_corrections" => { "quality_status" => "needs_review" } })

    post reject_custom_admin_agent_review_path(rejected_run)
    assert_redirected_to custom_admin_agent_review_path(rejected_run)
    assert_equal "rejected", rejected_run.reload.details["admin_decision"]["decision"]
    assert_equal original_attributes, company.reload.attributes.slice("quality_status", "verification_verdict", "quality_score", "description")

    post follow_up_custom_admin_agent_review_path(follow_up_run)
    assert_redirected_to custom_admin_agent_review_path(follow_up_run)
    assert_equal "needs_follow_up", follow_up_run.reload.details["admin_decision"]["decision"]
    assert_equal original_attributes, company.reload.attributes.slice("quality_status", "verification_verdict", "quality_score", "description")
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
