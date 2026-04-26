require "test_helper"

class ManualCompanyReviewServiceTest < ActiveSupport::TestCase
  test "creates a pipeline run with evidence and proposed corrections without changing company" do
    company = companies(:one)
    original_attributes = company.attributes.slice("name", "description", "main_url", "visible", "quality_status", "verification_verdict", "quality_score", "canonical_domain", "fingerprint")

    assert_difference "PipelineRun.count", 1 do
      @run = ManualCompanyReviewService.call(company: company, reviewer: "test@example.com", notes: "Manual smoke review")
    end

    assert_equal "succeeded", @run.status
    assert_equal "manual_company_review", @run.run_type
    assert_equal "ManualCompanyReviewService", @run.agent_name
    assert_equal company.id, @run.details["company_id"]
    assert_equal "manual_no_public_writes", @run.details["mode"]
    assert_not_empty @run.details["evidence"]
    assert_equal "needs_review", @run.details["proposed_corrections"]["quality_status"]
    assert_equal original_attributes, company.reload.attributes.slice("name", "description", "main_url", "visible", "quality_status", "verification_verdict", "quality_score", "canonical_domain", "fingerprint")
  end
end
