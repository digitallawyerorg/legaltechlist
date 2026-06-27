require "test_helper"

class CompanyProposalWorkflowTest < ActiveSupport::TestCase
  test "queues absent Atlas candidates as proposals without changing companies" do
    run = atlas_candidate_run
    original_count = Company.count

    assert_difference "CompanyProposal.count", 1 do
      proposals = CompanyProposalQueueService.call(pipeline_run: run, candidate_indexes: ["1"], admin_user: admin_users(:one))
      @proposal = proposals.first
    end

    assert_equal original_count, Company.count
    assert_equal "pending", @proposal.status
    assert_equal "New Atlas Candidate", @proposal.proposed_changes["name"]
    assert_equal "New source description must not be copied.", @proposal.source_payload["source_description"]
    assert_nil @proposal.final_changes["description"]
    assert_not @proposal.duplicate_blocking?
  end

  test "queue service ignores existing or duplicate candidates" do
    run = atlas_candidate_run

    assert_no_difference "CompanyProposal.count" do
      proposals = CompanyProposalQueueService.call(pipeline_run: run, candidate_indexes: ["0"], admin_user: admin_users(:one))
      assert_empty proposals
    end
  end

  test "proposal enrichment updates proposal only and does not copy source description" do
    proposal = queued_proposal
    original_company_count = Company.count

    CompanyProposalEnrichmentService.call(proposal: proposal, admin_user: admin_users(:one))

    proposal.reload
    assert_equal original_company_count, Company.count
    assert_equal "ready_for_review", proposal.status
    assert proposal.final_changes["description"].present?
    assert_not_equal proposal.source_payload["source_description"], proposal.final_changes["description"]
    assert_no_match(/provides or supports/i, proposal.final_changes["description"])
    assert_equal "CompanyProposalEnrichmentService", proposal.agent_details["agent"]
    assert_includes %w[pass revise], proposal.agent_details["description_critic"]["verdict"]
    assert_equal "disabled_no_responses_web_search", proposal.agent_details["web_research"]["mode"]
  end

  test "proposal enrichment drafts stronger descriptions from source evidence" do
    proposal = CompanyProposal.create!(
      status: "pending",
      proposal_type: "atlas_candidate",
      source: "legaltechatlas_csv",
      source_identifier: "august-law-test",
      source_payload: {
        "name" => "August",
        "website" => "https://www.august.law",
        "industries" => ["Artificial Intelligence (AI)", "Developer Platform", "Legal"],
        "source_description" => "August is a configurable legal AI platform designed specifically for law firms and legal professionals.",
        "full_source_description" => "August specializes in configurable legal AI platforms tailored for law firms and legal professionals."
      },
      proposed_changes: { "name" => "August", "main_url" => "https://www.august.law" },
      final_changes: { "name" => "August", "main_url" => "https://www.august.law" }
    )

    CompanyProposalEnrichmentService.call(proposal: proposal, admin_user: admin_users(:one))

    description = proposal.reload.final_changes["description"]
    assert_match(/legal AI software/i, description)
    assert_match(/law firms/i, description)
    assert_no_match(/provides or supports/i, description)
    assert_not_equal proposal.source_payload["source_description"], description
  end

  test "approval creates an invisible company draft from final fields" do
    proposal = ready_proposal
    original_company_count = Company.count

    company = nil
    assert_difference "Company.count", 1 do
      company = CompanyProposalApprovalService.call(proposal: proposal, admin_user: admin_users(:one))
    end

    assert_equal original_company_count + 1, Company.count
    assert_equal "New Atlas Candidate", company.name
    assert_equal "A neutral reviewed description for a new legal technology company.", company.description
    assert_not company.visible?
    assert_equal "needs_review", company.quality_status
    assert_equal "human_approved_candidate", company.verification_verdict
    assert_equal company, proposal.reload.company
    assert_equal "approved_to_draft", proposal.status
  end

  test "approval can publish the company when requested" do
    proposal = ready_proposal

    company = CompanyProposalApprovalService.call(proposal: proposal, admin_user: admin_users(:one), publish: true)

    assert company.visible?
    assert_equal "published", proposal.reload.status
  end

  test "publish is blocked when quality gates fail" do
    proposal = queued_proposal

    assert_no_difference "Company.count" do
      assert_raises(ArgumentError) do
        CompanyProposalApprovalService.call(proposal: proposal, admin_user: admin_users(:one), publish: true)
      end
    end
  end

  test "batch publish only publishes gate-passing proposals" do
    proposal = ready_proposal

    results = CompanyProposalBatchService.call(proposals: CompanyProposal.where(id: proposal.id), admin_user: admin_users(:one), action: "publish")

    assert_equal "published", proposal.reload.status
    assert_equal 1, results.size
    assert_equal proposal.company_id, results.first["company_id"]
  end

  test "approval generates a description when editable description is blank" do
    proposal = queued_proposal
    proposal.update!(
      final_changes: proposal.final_changes.merge(
        "description" => nil,
        "category_id" => categories(:one).id,
        "business_model_id" => business_models(:one).id,
        "target_client_id" => target_clients(:one).id
      )
    )

    company = CompanyProposalApprovalService.call(proposal: proposal, admin_user: admin_users(:one))

    assert company.description.present?
    assert_not_equal proposal.source_payload["source_description"], company.description
    assert_equal "approved_to_draft", proposal.reload.status
  end

  test "duplicate proposals require explicit approval override" do
    proposal = ready_proposal
    proposal.update!(duplicate_signals: { "name_matches" => [{ "id" => companies(:one).id, "name" => companies(:one).name }], "domain_matches" => [] })

    assert_no_difference "Company.count" do
      assert_raises(ArgumentError) do
        CompanyProposalApprovalService.call(proposal: proposal, admin_user: admin_users(:one))
      end
    end

    assert_difference "Company.count", 1 do
      CompanyProposalApprovalService.call(proposal: proposal, admin_user: admin_users(:one), duplicate_override: true)
    end
  end

  test "candidate import auto-drafts clean rows and routes exceptions to proposals" do
    run = nil

    assert_difference "Company.count", 1 do
      assert_difference "CompanyProposal.count", 3 do
        with_candidate_import_csv do |path|
          run = CompanyCandidateImportService.call(file: path, admin_user: admin_users(:one), notes: "Import automation test")
        end
      end
    end

    automation = run.details["automation"]
    assert_equal 3, automation["processed_rows"]
    assert_equal 1, automation["auto_drafted"]
    assert_equal 1, automation["needs_review"]
    assert_equal 1, automation["needs_duplicate_review"]

    clean_proposal = CompanyProposal.find_by!(source_identifier: "clean-research.example")
    assert_equal "approved_to_draft", clean_proposal.status
    assert clean_proposal.company
    assert_not clean_proposal.company.visible?
    assert_equal "automated_import_draft", clean_proposal.company.verification_verdict
    assert_equal categories(:one).id, clean_proposal.final_changes["category_id"]
    assert_equal business_models(:one).id, clean_proposal.final_changes["business_model_id"]
    assert_equal target_clients(:one).id, clean_proposal.final_changes["target_client_id"]

    ambiguous_proposal = CompanyProposal.find_by!(source_identifier: "ambiguous-import.example")
    assert_nil ambiguous_proposal.company
    assert_includes CompanyProposalQualityService.call(ambiguous_proposal)["missing_required_fields"], "category_id"

    duplicate_proposal = CompanyProposal.find_by!(source_identifier: "example.com")
    assert_nil duplicate_proposal.company
    assert duplicate_proposal.duplicate_blocking?
  end

  test "candidate import is idempotent by source identifier" do
    with_candidate_import_csv do |path|
      CompanyCandidateImportService.call(file: path, admin_user: admin_users(:one), notes: "First import automation test")
    end

    assert_no_difference "Company.count" do
      assert_no_difference "CompanyProposal.count" do
        with_candidate_import_csv do |path|
          CompanyCandidateImportService.call(file: path, admin_user: admin_users(:one), notes: "Second import automation test")
        end
      end
    end
  end

  test "taxonomy suggestions account for production category and client names" do
    analytics = Category.create!(name: "Analytics & Insights")
    data_analytics = BusinessModel.create!(name: "Data & Analytics")
    legal_service_providers = TargetClient.create!(name: "Legal Service Providers")

    suggestion = CompanyProposalTaxonomySuggestionService.call(
      source_payload: {
        "name" => "Insight Review",
        "industries" => ["Analytics", "Legal Tech", "Data"],
        "source_description" => "Insight Review develops analytics dashboards and reporting for legal service providers."
      }
    )

    assert suggestion["accepted"]
    assert_equal analytics.id, suggestion.dig("category", "id")
    assert_equal data_analytics.id, suggestion.dig("business_model", "id")
    assert_equal legal_service_providers.id, suggestion.dig("target_client", "id")
  end

  private

  def atlas_candidate_run
    AtlasCandidateImportReviewService.call(file: Rails.root.join("test/fixtures/atlas_candidates.csv"), reviewer: "test@example.com", notes: "Proposal workflow test")
  end

  def queued_proposal
    CompanyProposalQueueService.call(pipeline_run: atlas_candidate_run, candidate_indexes: ["1"], admin_user: admin_users(:one)).first
  end

  def ready_proposal
    proposal = queued_proposal
    proposal.update!(
      final_changes: proposal.final_changes.merge(
        "description" => "A neutral reviewed description for a new legal technology company.",
        "category_id" => categories(:one).id,
        "business_model_id" => business_models(:one).id,
        "target_client_id" => target_clients(:one).id
      )
    )
    proposal
  end

  def with_candidate_import_csv
    Tempfile.create(["candidate_import", ".csv"]) do |file|
      file.write(candidate_import_csv)
      file.close
      yield file.path
    end
  end

  def candidate_import_csv
    <<~CSV
      Organization Name,Organization Name URL,Industries,Founded Date,Headquarters Location,Description,Website,LinkedIn,Operating Status,Company Type,Total Funding Amount (in USD),Number of Funding Rounds,Number of Employees,Founders,Full Description
      Clean Research Candidate,https://www.crunchbase.com/organization/clean-research-candidate,"Legal Research, SaaS, Law Firms",2024-01-01,"Boston, Massachusetts, United States","Clean Research Candidate builds legal research software for law firms.",https://clean-research.example,https://www.linkedin.com/company/clean-research,Active,For Profit,1000000,1,1-10,Jane Founder,"Clean Research Candidate develops legal research software platforms for law firms and legal professionals."
      Ambiguous Import Candidate,https://www.crunchbase.com/organization/ambiguous-import-candidate,"Legal Tech",2025-01-01,"Austin, Texas, United States","Ambiguous Import Candidate builds legal technology.",https://ambiguous-import.example,https://www.linkedin.com/company/ambiguous-import,Active,For Profit,500000,1,1-10,Alex Founder,"Ambiguous Import Candidate develops legal technology."
      Test Company One,https://www.crunchbase.com/organization/test-company-one,"Legal Research, SaaS",2020-01-01,"San Francisco, California, United States","Duplicate of an existing company.",http://example.com,https://www.linkedin.com/company/test-company-one,Active,For Profit,1000000,1,1-10,Existing Founder,"Duplicate of an existing company."
    CSV
  end
end
