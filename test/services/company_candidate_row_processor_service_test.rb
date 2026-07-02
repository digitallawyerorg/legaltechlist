require "test_helper"
require "minitest/mock"

class CompanyCandidateRowProcessorServiceTest < ActiveSupport::TestCase
  test "discovery candidates arrive pre-classified from search taxonomy and cited year" do
    admin = AdminUser.create!(email: "rp-#{SecureRandom.hex(3)}@example.com", password: "password123", password_confirmation: "password123")
    candidate = {
      "name" => "Prefill Legal Co",
      "website" => "https://prefill-legal.example",
      "canonical_domain" => "prefill-legal.example",
      "location" => "Paris, France",
      "founded_date" => "2019",
      "category_name" => categories(:one).name,
      "business_model_names" => [business_models(:one).name],
      "target_client_names" => [target_clients(:one).name],
      "founded_year_source" => "https://linkedin.example/company/prefill",
      "status" => "absent_candidate"
    }

    CompanyCandidateRowProcessorService.call(
      candidate: candidate,
      index: 0,
      admin_user: admin,
      source: "llm_discovery",
      proposal_type: "discovery_candidate",
      source_label: "LLM Discovery",
      skip_auto_draft: true
    )

    proposal = CompanyProposal.find_by(source: "llm_discovery", source_identifier: "prefill-legal.example")
    assert proposal, "expected a discovery proposal to be created"
    assert_equal categories(:one).id, proposal.final_changes["category_id"]
    assert_equal [business_models(:one).id], proposal.final_changes["business_model_ids"]
    assert_equal [target_clients(:one).id], proposal.final_changes["target_client_ids"]
    assert proposal.agent_details.dig("taxonomy_suggestion", "accepted"), "taxonomy should be accepted when fully mapped"
    assert_equal "https://linkedin.example/company/prefill", proposal.agent_details.dig("founded_date_source", "source_url")
  end

  test "does not overwrite existing taxonomy on re-discovery" do
    admin = AdminUser.create!(email: "rp-#{SecureRandom.hex(3)}@example.com", password: "password123", password_confirmation: "password123")
    existing = CompanyProposal.create!(
      source: "llm_discovery",
      source_identifier: "keep-legal.example",
      proposal_type: "discovery_candidate",
      status: "ready_for_review",
      admin_user: admin,
      final_changes: { "name" => "Keep Legal", "category_id" => categories(:two).id },
      agent_details: { "taxonomy_suggestion" => { "accepted" => true, "mode" => "curator" } }
    )

    candidate = {
      "name" => "Keep Legal",
      "website" => "https://keep-legal.example",
      "canonical_domain" => "keep-legal.example",
      "category_name" => categories(:one).name,
      "business_model_names" => [business_models(:one).name],
      "target_client_names" => [target_clients(:one).name],
      "status" => "absent_candidate"
    }

    CompanyCandidateRowProcessorService.call(
      candidate: candidate,
      index: 0,
      admin_user: admin,
      source: "llm_discovery",
      proposal_type: "discovery_candidate",
      source_label: "LLM Discovery",
      skip_auto_draft: true
    )

    existing.reload
    assert_equal "curator", existing.agent_details.dig("taxonomy_suggestion", "mode")
    assert_equal categories(:two).id, existing.final_changes["category_id"]
  end

  test "clean drafted description is promoted at discovery time and skips enrichment" do
    admin = AdminUser.create!(email: "rp-#{SecureRandom.hex(3)}@example.com", password: "password123", password_confirmation: "password123")
    drafted = "Acme Legal develops contract review and clause extraction software for corporate legal teams to analyze agreements and monitor obligations across large document collections."
    candidate = {
      "name" => "Acme Legal Draft",
      "website" => "https://acme-draft.example",
      "canonical_domain" => "acme-draft.example",
      "location" => "London, United Kingdom",
      "founded_date" => "2020",
      "category_name" => categories(:one).name,
      "business_model_names" => [business_models(:one).name],
      "target_client_names" => [target_clients(:one).name],
      "discovery_description" => drafted,
      "status" => "absent_candidate"
    }

    CompanyProposalEnrichmentService.stub(:call, ->(*) { raise "enrichment should not run for a fully-drafted discovery candidate" }) do
      CompanyCandidateRowProcessorService.call(
        candidate: candidate,
        index: 0,
        admin_user: admin,
        source: "llm_discovery",
        proposal_type: "discovery_candidate",
        source_label: "LLM Discovery"
      )
    end

    proposal = CompanyProposal.find_by(source: "llm_discovery", source_identifier: "acme-draft.example")
    assert proposal, "expected a discovery proposal to be created"
    assert_equal drafted, proposal.final_changes["description"]
    assert_equal "pass", proposal.agent_details.dig("description_critic", "verdict")
    assert CompanyProposalQualityService.call(proposal)["publish_ready"], "confident discovery candidate should be publish-ready without enrichment"
  end

  test "weak drafted description is left for enrichment" do
    admin = AdminUser.create!(email: "rp-#{SecureRandom.hex(3)}@example.com", password: "password123", password_confirmation: "password123")
    candidate = {
      "name" => "Weak Draft Legal",
      "website" => "https://weak-draft.example",
      "canonical_domain" => "weak-draft.example",
      "category_name" => categories(:one).name,
      "business_model_names" => [business_models(:one).name],
      "target_client_names" => [target_clients(:one).name],
      "discovery_description" => "Legal tech company.",
      "status" => "absent_candidate"
    }

    CompanyCandidateRowProcessorService.call(
      candidate: candidate,
      index: 0,
      admin_user: admin,
      source: "llm_discovery",
      proposal_type: "discovery_candidate",
      source_label: "LLM Discovery",
      skip_auto_draft: true
    )

    proposal = CompanyProposal.find_by(source: "llm_discovery", source_identifier: "weak-draft.example")
    assert proposal, "expected a discovery proposal to be created"
    assert proposal.final_changes["description"].blank?, "weak draft should not be promoted"
    assert proposal.agent_details["description_critic"].blank?, "no critic verdict should be recorded for a rejected draft"
  end
end
