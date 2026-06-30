require "test_helper"

class CompanyReviewMarkServiceTest < ActiveSupport::TestCase
  test "mark verified sets quality fields and timestamps" do
    company = companies(:one)
    company.update_columns(quality_status: nil, verification_verdict: nil, human_reviewed_at: nil, verified_at: nil)

    CompanyReviewMarkService.call(company: company, decision: "verified")
    company.reload

    assert_equal "verified", company.quality_status
    assert_equal "human_confirmed", company.verification_verdict
    assert company.human_reviewed_at.present?
    assert company.quality_reviewed_at.present?
    assert company.verified_at.present?
  end

  test "mark needs work keeps company visible" do
    company = companies(:one)
    company.update_columns(quality_status: nil, visible: true)

    CompanyReviewMarkService.call(company: company, decision: "needs_work")
    company.reload

    assert_equal "needs_review", company.quality_status
    assert_equal "needs_human_review", company.verification_verdict
    assert company.visible?
  end

  test "mark reject hides company" do
    company = companies(:one)
    company.update_columns(quality_status: nil, visible: true)

    CompanyReviewMarkService.call(company: company, decision: "reject")
    company.reload

    assert_equal "rejected", company.quality_status
    assert_equal "human_rejected", company.verification_verdict
    assert_not company.visible?
  end

  test "raises for unknown decision" do
    assert_raises(ArgumentError) do
      CompanyReviewMarkService.call(company: companies(:one), decision: "unknown")
    end
  end
end
