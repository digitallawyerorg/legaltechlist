require "test_helper"

class TaxonomyCompletenessTest < ActiveSupport::TestCase
  test "detects missing taxonomy when only m2m arrays are absent" do
    proposal = CompanyProposal.new(
      status: "pending",
      proposal_type: "atlas_candidate",
      source: "test",
      final_changes: { "category_id" => "1" }
    )

    assert_includes proposal.missing_taxonomy_field_keys, "business_model_id"
    assert_includes proposal.missing_taxonomy_field_keys, "target_client_id"
  end

  test "accepts m2m revenue and target client ids as complete" do
    proposal = CompanyProposal.new(
      status: "pending",
      proposal_type: "atlas_candidate",
      source: "test",
      final_changes: {
        "category_id" => "1",
        "business_model_ids" => ["2"],
        "target_client_ids" => ["3"]
      }
    )

    assert_empty proposal.missing_taxonomy_field_keys
    assert proposal.revenue_models_present?
    assert proposal.target_clients_present?
  end
end

class CompanyProposalQualityServiceM2mTest < ActiveSupport::TestCase
  test "does not require singular fk when m2m taxonomy is present" do
    proposal = CompanyProposal.create!(
      status: "ready_for_review",
      proposal_type: "atlas_candidate",
      source: "test",
      source_identifier: "m2m-quality-test",
      final_changes: {
        "name" => "Example Legal Tech Co",
        "main_url" => "https://example.com",
        "location" => "Stanford, CA",
        "founded_date" => "2020",
        "description" => "Example Legal Tech Co provides contract management software for in-house legal teams and law firms.",
        "category_id" => categories(:one).id.to_s,
        "business_model_ids" => [business_models(:one).id.to_s],
        "target_client_ids" => [target_clients(:one).id.to_s]
      },
      agent_details: { "description_critic" => { "verdict" => "pass" } }
    )

    quality = CompanyProposalQualityService.call(proposal)

    refute_includes quality["missing_required_fields"], "business_model_id"
    refute_includes quality["missing_required_fields"], "target_client_id"
  end
end
