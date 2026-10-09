require "test_helper"

class CompanyProposalQualityServiceTest < ActiveSupport::TestCase
  def quality_for(changes)
    proposal = CompanyProposal.new(status: "pending", proposal_type: "user_contribution", source: "user_contribution",
                                   proposed_changes: changes, final_changes: changes)
    CompanyProposalQualityService.call(proposal)
  end

  # Proposal 5731: every field filled, description critic "pass", score 100.
  test "a fully filled record with nothing about legal work is flagged and cannot autopublish" do
    quality = quality_for(
      "name" => "Custom T-Shirt UAE", "main_url" => "https://www.customtshirts.ae/", "location" => "Dubai",
      "founded_date" => "2012", "category_id" => categories(:one).id,
      "description" => "Equip the field service team with hardwearing equipment. Choose personalized t shirts in Dubai with reinforced seams."
    )

    assert_equal false, quality["legal_signal"]
    assert quality["score"] < 100
    assert(quality["warnings"].any? { |warning| warning.include?("legal work") })
  end

  test "a legal technology record has a legal signal" do
    quality = quality_for("name" => "Afriwise", "main_url" => "https://www.afriwise.com",
                          "description" => "Afriwise is a legal and regulatory information platform covering African jurisdictions.")
    assert quality["legal_signal"]
  end
end
