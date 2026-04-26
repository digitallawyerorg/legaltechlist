require "test_helper"

class CompanyAgentReviewServiceTest < ActiveSupport::TestCase
  test "creates proposal-only evidence and verifier output without changing company" do
    company = companies(:one)
    original_attributes = tracked_company_attributes(company)

    assert_difference "PipelineRun.count", 1 do
      @run = CompanyAgentReviewService.call(company: company, reviewer: "test@example.com", notes: "Agent proposal test")
    end

    assert_equal "succeeded", @run.status
    assert_equal "company_agent_review", @run.run_type
    assert_equal "CompanyEvidenceAgent+CompanyVerifierAgent", @run.agent_name
    assert_equal company.id, @run.details["company_id"]
    assert_equal "agent_proposal_no_public_writes", @run.details["mode"]
    assert_not_empty @run.details["evidence"]
    assert_includes @run.details["verification"].keys, "verdict"
    assert_includes @run.details["verification"].keys, "quality_score"
    assert_equal "needs_review", @run.details["proposed_corrections"]["quality_status"]
    assert_equal original_attributes, tracked_company_attributes(company.reload)
  end

  test "verifier flags weak descriptions as risks" do
    company = companies(:one)
    company.update_columns(description: "Short")

    run = CompanyAgentReviewService.call(company: company)

    assert_includes run.details["risks"], "Weak or short description."
    assert_equal "Draft a new neutral, source-backed TechIndex description before marking reviewed.", run.details["proposed_corrections"]["description_review"]
  end

  private

  def tracked_company_attributes(company)
    company.attributes.slice("name", "description", "main_url", "visible", "quality_status", "verification_verdict", "quality_score", "canonical_domain", "fingerprint")
  end
end
