require "test_helper"

class CustomAdminTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "custom admin redirects unauthenticated users to login" do
    get custom_admin_root_path

    assert_redirected_to custom_admin_companies_path
    follow_redirect!
    assert_redirected_to new_admin_user_session_path
  end

  test "signed-in admin visiting login page redirects to companies index" do
    sign_in admin_users(:one)

    get new_admin_user_session_path

    assert_redirected_to custom_admin_companies_path
  end

  test "admin login page uses centered styled form" do
    get new_admin_user_session_path

    assert_response :success
    assert_select ".min-vh-100.d-flex.align-items-center"
    assert_select ".card .card-body h1", "TechIndex Admin"
    assert_select "form[action='#{admin_user_session_path}'][method='post']"
    assert_select "input.form-control[name='admin_user[email]']"
    assert_select "input.form-control[name='admin_user[password]']"
    assert_select "input.btn.btn-dark[type='submit'][value='Log in']"
  end

  test "custom admin landing redirects signed-in admin users to companies index" do
    sign_in admin_users(:one)

    get custom_admin_root_path

    assert_redirected_to custom_admin_companies_path
    follow_redirect!
    assert_response :success
    assert_select "h1", "Companies"
    assert_select "nav a", "Companies"
    assert_select "nav a", "Review"
    assert_select "nav a", "Activity"
    assert_select "a.btn.btn-primary[href='#{new_custom_admin_company_path}']", text: /Add Company/
    assert_select ".admin-user-dropdown .dropdown-toggle", text: admin_users(:one).email
    assert_select ".admin-user-dropdown form[action='#{destroy_admin_user_session_path}'][method='post'] input[name='_method'][value='delete']"
    assert_select ".admin-user-dropdown .dropdown-item[type='submit']", "Log out"
    assert_select ".admin-user-dropdown .dropdown-item", "Public Site"
  end

  test "admin logout signs out with delete request" do
    sign_in admin_users(:one)

    delete destroy_admin_user_session_path

    assert_redirected_to root_path

    get custom_admin_root_path
    assert_redirected_to custom_admin_companies_path
    follow_redirect!
    assert_redirected_to new_admin_user_session_path
  end

  test "quality dashboard is available to signed-in admin users" do
    sign_in admin_users(:one)

    get custom_admin_quality_path

    assert_response :success
    assert_select "h1", "Quality Dashboard"
    assert_select ".admin-quality-label", text: "Missing URLs"
    assert_select ".admin-quality-label", text: "Duplicate-domain candidates"
  end

  test "company review index redirects to proposal review" do
    sign_in admin_users(:one)

    get custom_admin_company_reviews_path

    assert_redirected_to custom_admin_company_proposals_path
  end

  test "description review queue is available on companies tab" do
    sign_in admin_users(:one)
    company = companies(:one)
    company.update_columns(description: "Short")

    get custom_admin_companies_path(review_signal: "description_review")

    assert_response :success
    assert_select "h1", "Companies"
    assert_select "td", text: /#{Regexp.escape(company.name)}/
  end

  test "company review show is available to signed-in admin users" do
    sign_in admin_users(:one)

    get custom_admin_company_review_path(companies(:one))

    assert_response :success
    assert_select "h1", companies(:one).name
    assert_select "h2", "Core Data"
    assert_select "h2", "Links"
    assert_select "h2", "People And Funding"
    assert_select "h2", "Source And Events"
    assert_select "h2", "System Metadata"
    assert_select "a", "Edit Company"
    assert_select "button", "Mark verified"
    assert_select "button", "Needs more work"
    assert_select "button", "Reject and hide"
    assert_select "button", "Agent review"
    assert_select "button", "Duplicate review"
    assert_select "button", "Delete"
    assert_select "a", { text: "Back to Companies", count: 0 }
  end

  test "company mark review updates quality state" do
    sign_in admin_users(:one)
    company = companies(:one)
    company.update_columns(quality_status: nil, verification_verdict: nil, human_reviewed_at: nil, verified_at: nil)

    post custom_admin_company_mark_review_path(company), params: { decision: "verified" }

    assert_redirected_to custom_admin_company_review_path(company)
    company.reload
    assert_equal "verified", company.quality_status
    assert_equal "human_confirmed", company.verification_verdict
    assert company.human_reviewed_at.present?
  end

  test "companies index supports review state filter" do
    sign_in admin_users(:one)
    companies(:one).update_columns(quality_status: nil, human_reviewed_at: nil)
    companies(:two).update_columns(quality_status: "verified", human_reviewed_at: Time.current)

    get custom_admin_companies_path(review_state: "not_reviewed")

    assert_response :success
    assert_select "td", text: /#{Regexp.escape(companies(:one).name)}/
    assert_no_match companies(:two).name, response.body
    assert_select ".admin-status-pill", text: "Not reviewed"
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
    assert_select "h1", "Activity"
    assert_select ".admin-section-tabs a.active", "All Runs"
    assert_select ".admin-section-tabs a", "Agent Reviews"
    assert_select "td a", text: /Manual verifier/

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
    assert_select ".admin-section-tabs a.active", "Agent Reviews"
    assert_select ".admin-section-tabs a", "All Runs"
    assert_select "td a", text: /Agent review sample/

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

  test "fill from url requires authentication" do
    post fill_from_url_custom_admin_company_path, params: { company: { name: "Manual Entry Co", main_url: "https://manual-entry.example" } }

    assert_redirected_to new_admin_user_session_path
  end

  test "fill from url requires name and url" do
    sign_in admin_users(:one)

    post fill_from_url_custom_admin_company_path, params: { company: { name: "", main_url: "" } }

    assert_redirected_to new_custom_admin_company_path
    assert_match(/required/i, flash[:alert])
  end

  test "fill from url creates proposal and redirects to edit" do
    sign_in admin_users(:one)
    original_call = CompanyProposalEnrichmentService.method(:call)
    CompanyProposalEnrichmentService.define_singleton_method(:call) do |**kwargs|
      proposal = kwargs[:proposal]
      proposal.update!(status: "ready_for_review", final_changes: proposal.final_changes.merge("description" => "Enriched description."))
      proposal
    end

    assert_difference "CompanyProposal.count", 1 do
      post fill_from_url_custom_admin_company_path, params: { company: { name: "Manual Entry Co", main_url: "https://manual-entry.example" } }
    end

    proposal = CompanyProposal.order(:created_at).last
    assert_redirected_to edit_custom_admin_company_proposal_path(proposal)
    assert_equal "admin_manual_entry", proposal.source
    assert_equal "atlas_candidate", proposal.proposal_type
    assert_equal "Manual Entry Co", proposal.display_name
  ensure
    CompanyProposalEnrichmentService.define_singleton_method(:call, original_call)
  end

  test "custom company management supports edit and export" do
    sign_in admin_users(:one)
    company = companies(:one)

    get custom_admin_companies_path
    assert_response :success
    assert_select "h1", "Companies"
    assert_select ".admin-filter-toolbar"
    assert_select "input[name='q']"
    assert_select "select[name='visibility']"
    assert_select "select[name='review_signal']"
    assert_select "select[name='review_state']"
    assert_select "a[href='#{custom_admin_companies_path(review_signal: 'missing_url')}']"
    assert_select "form[action='#{custom_admin_company_path(company)}'][method='post'] input[name='_method'][value='delete']"
    assert_select "button", "Delete"

    companies(:two).update_columns(visible: false)
    get custom_admin_companies_path(visibility: "hidden")
    assert_response :success
    assert_select "td", text: /#{Regexp.escape(companies(:two).name)}/
    assert_no_match companies(:one).name, response.body

    get custom_admin_companies_path(q: "Company One")
    assert_response :success
    assert_select "td", text: /#{Regexp.escape(companies(:one).name)}/

    get edit_custom_admin_company_path(company)
    assert_response :success
    assert_select "h1", "Edit #{company.name}"
    assert_select "input[name='company[codex_presenter]'][type='checkbox']"
    assert_select "input[name='company[codex_presentation_date]'][type='date']"
    assert_select "input[name='company[legaltech_atlas_url]']"

    get new_custom_admin_company_path
    assert_response :success
    assert_select "h1", "New Company"
    assert_select "input[name='company[codex_presenter]'][type='checkbox']"
    assert_select "input[name='company[codex_presentation_date]'][type='date']"

    compound_target_client = TargetClient.create!(name: "Corporate Legal, Law Firms", description: "Legacy compound")
    compound_revenue_model = BusinessModel.create!(name: "Subscription, Services", description: "Legacy compound")
    get edit_custom_admin_company_path(company)
    checkbox_labels = css_select("label.form-check-label").map(&:text)
    refute_includes checkbox_labels, compound_target_client.name
    refute_includes checkbox_labels, compound_revenue_model.name
    refute checkbox_labels.any? { |label| label.include?(",") }, "expected no combinatorial checkbox labels"
    assert_equal BusinessModel.canonical.order(:name).pluck(:name), checkbox_labels & BusinessModel.canonical.pluck(:name)
    assert_equal TargetClient.canonical.order(:name).pluck(:name), checkbox_labels & TargetClient.canonical.pluck(:name)

    patch custom_admin_company_path(company), params: { company: { name: "Custom Managed Company", description: company.description, main_url: company.main_url, visible: company.visible, category_id: company.category_id, business_model_id: company.business_model_id, target_client_id: company.target_client_id, secondary_category_id: company.secondary_category_id } }
    assert_redirected_to custom_admin_company_review_path(company)
    assert_equal "Custom Managed Company", company.reload.name

    get upload_custom_admin_companies_csv_path
    assert_response :success
    assert_select "input[type=submit][value='Process Candidates']"

    get export_custom_admin_companies_csv_path
    assert_response :success
    assert_includes response.media_type, "text/csv"
  end

  test "company deletion is admin-only and removes the company record" do
    company = companies(:one)

    delete company_path(company)
    assert_response :not_found
    assert Company.exists?(company.id)

    delete custom_admin_company_path(company)
    assert_redirected_to new_admin_user_session_path
    assert Company.exists?(company.id)

    sign_in admin_users(:one)
    proposal = CompanyProposal.create!(status: "approved_to_draft", proposal_type: "atlas_candidate", source: "test", source_identifier: "delete-test", company: company)

    assert_difference "Company.count", -1 do
      delete custom_admin_company_path(company)
    end

    assert_redirected_to custom_admin_companies_path
    assert_not Company.exists?(company.id)
    assert_nil proposal.reload.company_id
  end

  test "candidate import processing creates proposals without publishing companies" do
    sign_in admin_users(:one)
    file = Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/atlas_candidates.csv"), "text/csv")
    original_count = Company.count
    unchanged_fields = %w[name description main_url visible quality_status verification_verdict quality_score]
    original_attributes = companies(:one).attributes.slice(*unchanged_fields)

    assert_difference "PipelineRun.count", 1 do
      assert_difference "CompanyProposal.count", 2 do
        post review_import_candidates_custom_admin_companies_csv_path, params: { dump: { file: file } }
      end
    end

    run = PipelineRun.order(:created_at).last
    assert_redirected_to custom_admin_company_proposals_path
    assert_equal "atlas_candidate_import_review", run.run_type
    assert_equal "candidate_import_review_no_public_writes", run.details["mode"]
    assert_equal 2, run.details["summary"]["reviewed_rows"]
    assert_equal 2, run.details["automation"]["processed_rows"]
    assert_equal original_count, Company.count
    assert_equal original_attributes, companies(:one).reload.attributes.slice(*unchanged_fields)

    get custom_admin_pipeline_run_path(run)
    assert_response :success
    assert_select "h2", "Candidate Import Review"
    assert_select ".alert", /Source descriptions must not be copied/
    assert_select "td", text: /New Atlas Candidate/
  end

  test "candidate import review can queue absent candidates as editable proposals" do
    sign_in admin_users(:one)
    run = AtlasCandidateImportReviewService.call(file: Rails.root.join("test/fixtures/atlas_candidates.csv"), reviewer: "test@example.com", notes: "Queue proposals integration")
    original_count = Company.count

    assert_difference "CompanyProposal.count", 1 do
      assert_no_difference "Company.count" do
        post custom_admin_pipeline_run_company_proposals_path(run), params: { candidate_indexes: ["1"] }
      end
    end

    proposal = CompanyProposal.order(:created_at).last
    assert_redirected_to custom_admin_company_proposals_path
    assert_equal original_count, Company.count
    assert_equal "New Atlas Candidate", proposal.display_name
    assert proposal.final_changes["description"].present?
  end

  test "proposal admin workflow edits enriches and approves invisible company drafts" do
    sign_in admin_users(:one)
    proposal = CompanyProposal.create!(
      status: "pending",
      proposal_type: "atlas_candidate",
      source: "legaltechatlas_csv",
      source_identifier: "review-proposal.example",
      source_payload: { "name" => "Review Proposal", "website" => "https://review-proposal.example", "source_description" => "Do not copy this source description.", "industries" => ["Legal Tech"] },
      proposed_changes: { "name" => "Review Proposal", "main_url" => "https://review-proposal.example", "location" => "Chicago, IL", "founded_date" => "2024", "status" => "active", "source" => "LegalTechAtlas CSV", "source_url" => "https://review-proposal.example" },
      final_changes: { "name" => "Review Proposal", "main_url" => "https://review-proposal.example", "location" => "Chicago, IL", "founded_date" => "2024", "status" => "active", "source" => "LegalTechAtlas CSV", "source_url" => "https://review-proposal.example" }
    )

    get custom_admin_company_proposals_path
    assert_response :success
    assert_select "h1", "Review"
    assert_select ".admin-section-tabs", false
    assert_select ".admin-proposal-batch-actions.d-none"
    assert_select "input[data-proposal-select-all]"
    assert_select "button", "Re-enrich selected"
    assert_select "button", "Mark needs revision"
    assert_select "button", "Publish selected"
    assert_no_match(/Batch actions/, response.body)
    assert_select "td", text: /Review Proposal/
    assert_select ".admin-table-summary-item", text: /Ready/

    get custom_admin_company_proposal_path(proposal)
    assert_response :success
    assert_select "h1", "Review Proposal"
    assert_select "button", "Enrich"

    post enrich_custom_admin_company_proposal_path(proposal)
    assert_redirected_to custom_admin_company_proposal_path(proposal)
    assert_equal "ready_for_review", proposal.reload.status
    assert proposal.final_changes["description"].present?

    reviewed_description = "Review Proposal develops workflow software for legal teams reviewing intake, matter information, and related operational records."
    patch custom_admin_company_proposal_path(proposal), params: { company_proposal: { reviewer_notes: "Reviewed by admin.", final_changes: { name: "Review Proposal", main_url: "https://review-proposal.example", location: "Chicago, IL", founded_date: "2024", status: "active", description: reviewed_description, category_id: categories(:one).id, business_model_id: business_models(:one).id, target_client_id: target_clients(:one).id, source: "LegalTechAtlas CSV", source_url: "https://review-proposal.example" } } }
    assert_redirected_to custom_admin_company_proposal_path(proposal)

    assert_difference "Company.count", 1 do
      post approve_custom_admin_company_proposal_path(proposal), params: { publish: "1" }
    end

    company = proposal.reload.company
    assert_redirected_to custom_admin_company_review_path(company)
    assert company.visible?
    assert_equal "published", proposal.status
    assert_equal "Review Proposal", company.name
    assert_equal reviewed_description, company.description
  end

  test "proposal edit shows canonical revenue model and target client checkboxes only" do
    sign_in admin_users(:one)
    proposal = CompanyProposal.create!(
      status: "pending",
      proposal_type: "atlas_candidate",
      source: "legaltechatlas_csv",
      source_identifier: "edit-form.example",
      source_payload: { "name" => "Edit Form Proposal", "website" => "https://edit-form.example" },
      proposed_changes: { "name" => "Edit Form Proposal", "main_url" => "https://edit-form.example" },
      final_changes: { "name" => "Edit Form Proposal", "main_url" => "https://edit-form.example" }
    )
    compound_target_client = TargetClient.create!(name: "Companies, Corporate Legal, Legal Service Providers", description: "Legacy compound")
    compound_revenue_model = BusinessModel.create!(name: "Subscription, Services", description: "Legacy compound")

    get edit_custom_admin_company_proposal_path(proposal)

    assert_response :success
    assert_select "h1", "Edit Edit Form Proposal"
    checkbox_labels = css_select("label.form-check-label").map(&:text)
    refute_includes checkbox_labels, compound_target_client.name
    refute_includes checkbox_labels, compound_revenue_model.name
    refute checkbox_labels.any? { |label| label.include?(",") }, "expected no combinatorial checkbox labels"
    assert_equal BusinessModel.canonical.order(:name).pluck(:name), checkbox_labels & BusinessModel.canonical.pluck(:name)
    assert_equal TargetClient.canonical.order(:name).pluck(:name), checkbox_labels & TargetClient.canonical.pluck(:name)
  end

  test "proposal batch action marks selected proposals as needs revision" do
    sign_in admin_users(:one)
    proposal = CompanyProposal.create!(
      status: "pending",
      proposal_type: "atlas_candidate",
      source: "legaltechatlas_csv",
      source_identifier: "batch-review.example",
      source_payload: { "name" => "Batch Review", "website" => "https://batch-review.example" },
      proposed_changes: { "name" => "Batch Review", "main_url" => "https://batch-review.example" },
      final_changes: { "name" => "Batch Review", "main_url" => "https://batch-review.example" }
    )

    post batch_custom_admin_company_proposals_path, params: { proposal_ids: [proposal.id], batch_action: "mark_needs_revision", status: "pending_review" }

    assert_redirected_to custom_admin_company_proposals_path(status: "pending_review")
    assert_equal "needs_revision", proposal.reload.status
  end

  StubDiscoverySearchService = Class.new do
    def self.call(**kwargs)
      {
        "mode" => "stub",
        "discovery_type" => kwargs[:discovery_type],
        "query" => "stub query",
        "companies" => [
          {
            "name" => "Admin Discovery Co",
            "website" => "https://admin-discovery.example",
            "location" => "Austin, TX",
            "founded_date" => "2024",
            "description" => "Provides legal workflow automation.",
            "why_discovered" => "Matches category search.",
            "discovery_type" => kwargs[:discovery_type],
            "discovery_query" => "stub query",
            "website_verified" => true
          }
        ],
        "raw_search_call_count" => 1,
        "generated_at" => Time.current.utc.iso8601
      }
    end
  end

  test "discovery new requires authentication" do
    get new_custom_admin_discovery_path

    assert_redirected_to new_admin_user_session_path
  end

  test "discovery new page is available to signed-in admin users" do
    sign_in admin_users(:one)

    get new_custom_admin_discovery_path

    assert_response :success
    assert_select "h1", "LLM Company Discovery"
    assert_select "input[type=submit][value='Preview (dry run)']"
    assert_select "input[type=submit][value='Discover & queue all absent']"
    assert_select "nav a", "Discover"
  end

  test "discovery preview creates pipeline run without proposals" do
    sign_in admin_users(:one)
    original_call = CompanyDiscoveryService.method(:call)
    CompanyDiscoveryService.define_singleton_method(:call) do |**kwargs|
      original_call.call(**kwargs.merge(search_service: StubDiscoverySearchService))
    end

    assert_difference "PipelineRun.count", 1 do
      assert_no_difference "CompanyProposal.count" do
        post custom_admin_discoveries_path, params: {
          discovery: {
            discovery_type: "category",
            category_id: categories(:one).id,
            limit: 10,
            notes: "Admin preview test"
          },
          commit: "Preview (dry run)"
        }
      end
    end

    run = PipelineRun.order(:created_at).last
    assert_redirected_to custom_admin_pipeline_run_path(run)
    assert_equal "company_discovery", run.run_type
    assert_equal true, run.details["dry_run"]
    assert_equal 1, run.details["summary"]["absent_candidates"]
    follow_redirect!
    assert_select "h2", "LLM Discovery Review"
    assert_select "input[type=submit][value='Queue Selected Absent Candidates']"
  ensure
    CompanyDiscoveryService.define_singleton_method(:call, original_call)
  end

  test "discovery queue from pipeline run creates proposal for absent candidate" do
    sign_in admin_users(:one)
    run = CompanyDiscoveryService.call(
      discovery_type: "category",
      category: categories(:one).name,
      dry_run: true,
      search_service: StubDiscoverySearchService,
      admin_user: admin_users(:one),
      reviewer: admin_users(:one).email
    )

    assert_difference "CompanyProposal.count", 1 do
      post custom_admin_pipeline_run_company_proposals_path(run), params: { candidate_indexes: ["0"] }
    end

    proposal = CompanyProposal.order(:created_at).last
    assert_redirected_to custom_admin_company_proposals_path
    assert_equal "llm_discovery", proposal.source
    assert_equal "discovery_candidate", proposal.proposal_type
    assert_equal "Admin Discovery Co", proposal.display_name
    assert_nil proposal.company
  end
end
