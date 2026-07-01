require "test_helper"

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
end
