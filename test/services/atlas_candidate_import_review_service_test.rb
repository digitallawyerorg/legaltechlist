require "test_helper"

class AtlasCandidateImportReviewServiceTest < ActiveSupport::TestCase
  test "creates review-only candidate import run without changing companies" do
    original_count = Company.count
    existing_company = companies(:one)
    original_attributes = tracked_company_attributes(existing_company)
    file_path = Rails.root.join("test/fixtures/atlas_candidates.csv")

    assert_difference "PipelineRun.count", 1 do
      @run = AtlasCandidateImportReviewService.call(file: file_path, reviewer: "test@example.com", notes: "Candidate review test", limit: 10)
    end

    assert_equal original_count, Company.count
    assert_equal original_attributes, tracked_company_attributes(existing_company.reload)
    assert_equal "succeeded", @run.status
    assert_equal "atlas_candidate_import_review", @run.run_type
    assert_equal "AtlasCandidateImportReviewService", @run.agent_name
    assert_equal "candidate_import_review_no_public_writes", @run.details["mode"]
    assert_equal 2, @run.details["summary"]["reviewed_rows"]
    assert_equal 1, @run.details["summary"]["absent_candidates"]
    assert_equal "existing_or_possible_duplicate", @run.details["candidates"].first["status"]
    assert_equal "absent_candidate", @run.details["candidates"].last["status"]
    assert_equal "Do not copy into TechIndex. Use only as evidence for a new neutral description after human review.", @run.details["candidates"].last["source_description_policy"]
  end

  test "rejects limits above max limit" do
    error = assert_raises(ArgumentError) do
      AtlasCandidateImportReviewService.call(file: Rails.root.join("test/fixtures/atlas_candidates.csv"), limit: 1_001, max_limit: 1_000)
    end

    assert_match(/exceeds max_limit/, error.message)
  end

  private

  def tracked_company_attributes(company)
    company.attributes.slice("name", "description", "main_url", "visible", "quality_status", "verification_verdict", "quality_score", "canonical_domain", "fingerprint", "updated_at")
  end
end
