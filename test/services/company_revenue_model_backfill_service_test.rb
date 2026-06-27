require "test_helper"

class CompanyRevenueModelBackfillServiceTest < ActiveSupport::TestCase
  test "skips human reviewed companies" do
    company = companies(:one)
    company.update_columns(human_reviewed_at: Time.current)

    result = CompanyRevenueModelBackfillService.call(company: company)

    assert_equal "skipped_human_reviewed", result["action"]
  end

  test "boosts grants and subsidies for strong nonprofit signals" do
    company = companies(:one)
    company.update_columns(human_reviewed_at: nil, description: "Grant-funded legal aid platform for self-represented litigants.")
    company.tags << Tag.create!(name: "legal aid")
    company.tags << Tag.create!(name: "nonprofit")
    company.business_model_ids = []

    result = CompanyRevenueModelBackfillService.call(company: company, dry_run: true)

    assert_includes result["suggested_revenue_models"], "Grants & Subsidies"
    assert result["confidence"] >= CompanyRevenueModelBackfillService::HIGH_CONFIDENCE
  end
end
