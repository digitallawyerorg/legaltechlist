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
    assert_equal "disabled_no_search_api_key", proposal.agent_details["web_research"]["mode"]
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
end
