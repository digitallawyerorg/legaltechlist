require "test_helper"

class DuplicateDomainReviewServiceTest < ActiveSupport::TestCase
  test "creates proposal-only duplicate review without changing companies" do
    company = companies(:one)
    candidate = companies(:two)
    candidate.update_columns(main_url: "https://www.example.com", canonical_domain: nil)
    original_company_attributes = tracked_company_attributes(company.reload)
    original_candidate_attributes = tracked_company_attributes(candidate.reload)

    assert_difference "PipelineRun.count", 1 do
      @run = DuplicateDomainReviewService.call(company: company, reviewer: "test@example.com", notes: "Duplicate review test")
    end

    assert_equal "succeeded", @run.status
    assert_equal "duplicate_domain_review", @run.run_type
    assert_equal "DuplicateReviewAgent", @run.agent_name
    assert_equal "duplicate_review_no_public_writes", @run.details["mode"]
    assert_equal company.id, @run.details["company_id"]
    assert_includes @run.details["candidate_company_ids"], candidate.id
    assert_equal "DuplicateReviewSchema", @run.details["duplicate_review"]["schema"]
    assert_equal DuplicateReviewSchema::SCHEMA_VERSION, @run.details["duplicate_review"]["schema_version"]
    assert_includes DuplicateReviewAgent::OVERALL_RECOMMENDATIONS, @run.details["duplicate_review"]["overall_recommendation"]
    assert_includes DuplicateReviewAgent::RELATIONSHIPS, @run.details["duplicate_review"]["pair_reviews"].first["relationship"]
    assert_equal @run.details["duplicate_review"]["overall_recommendation"], @run.details["proposed_corrections"]["duplicate_review_recommendation"]
    assert_includes @run.details["risks"], "Human review required before merge, deletion, hiding, or overwrite."
    assert_equal original_company_attributes, tracked_company_attributes(company.reload)
    assert_equal original_candidate_attributes, tracked_company_attributes(candidate.reload)
  end

  test "duplicate review agent distinguishes exact duplicate signals from related domain signals" do
    company = companies(:one)
    candidate = companies(:two)
    candidate.update_columns(name: company.name, main_url: company.main_url)

    review = DuplicateReviewAgent.call(company, candidates: [candidate])

    assert_equal "deterministic_fallback", review["mode"]
    assert_equal "duplicate", review["pair_reviews"].first["relationship"]
    assert_equal company.description, company.reload.description
    assert_equal candidate.description, candidate.reload.description
  end

  private

  def tracked_company_attributes(company)
    company.attributes.slice("name", "description", "main_url", "visible", "quality_status", "verification_verdict", "quality_score", "canonical_domain", "fingerprint", "updated_at")
  end
end
