require "test_helper"

class AgentReviewBatchServiceTest < ActiveSupport::TestCase
  test "dry run records candidates without creating child review runs or changing companies" do
    company = companies(:one)
    company.update_columns(description: "Short", updated_at: 1.day.ago)
    original_attributes = tracked_company_attributes(company.reload)

    assert_difference "PipelineRun.count", 1 do
      @run = AgentReviewBatchService.call(review_type: "description", limit: 1, dry_run: true, reviewer: "test@example.com")
    end

    assert_equal "succeeded", @run.status
    assert_equal "agent_review_batch", @run.run_type
    assert_equal "AgentReviewBatchService", @run.agent_name
    assert_equal true, @run.details["dry_run"]
    assert_equal "description", @run.details["review_type"]
    assert_equal [company.id], @run.details["candidate_company_ids"]
    assert_empty @run.details["child_review_run_ids"]
    assert_equal "Dry run only; no child review runs were created.", @run.details["summary"]["dry_run_message"]
    assert_equal original_attributes, tracked_company_attributes(company.reload)
  end

  test "execution creates summary and child description review without changing company" do
    company = companies(:one)
    company.update_columns(description: "Short", updated_at: 1.day.ago)
    original_attributes = tracked_company_attributes(company.reload)

    assert_difference "PipelineRun.count", 2 do
      @run = AgentReviewBatchService.call(review_type: "description", limit: 1, dry_run: false, reviewer: "test@example.com", max_cost_usd: 1)
    end

    assert_equal false, @run.details["dry_run"]
    assert_equal 1, @run.details["child_review_run_ids"].size
    child_run = PipelineRun.find(@run.details["child_review_run_ids"].first)
    assert_equal "company_agent_review", child_run.run_type
    assert_equal 1, @run.details["summary"]["executed_count"]
    assert_equal original_attributes, tracked_company_attributes(company.reload)
  end

  test "duplicate-domain batch tracks candidate records without changing either company" do
    company = companies(:one)
    candidate = companies(:two)
    company.update_columns(main_url: "https://duplicate-batch.example.com", canonical_domain: nil, updated_at: 2.days.ago)
    candidate.update_columns(main_url: "https://www.duplicate-batch.example.com", canonical_domain: nil, updated_at: 1.day.ago)
    original_attributes = tracked_company_attributes(company.reload)
    original_candidate_attributes = tracked_company_attributes(candidate.reload)

    assert_difference "PipelineRun.count", 2 do
      @run = AgentReviewBatchService.call(review_type: "duplicate_domain", limit: 1, dry_run: false, reviewer: "test@example.com", max_cost_usd: 1)
    end

    assert_equal "duplicate_domain", @run.details["review_type"]
    assert_equal [company.id], @run.details["candidate_company_ids"]
    child_run = PipelineRun.find(@run.details["child_review_run_ids"].first)
    assert_equal "duplicate_domain_review", child_run.run_type
    assert_includes child_run.details["candidate_company_ids"], candidate.id
    assert_equal original_attributes, tracked_company_attributes(company.reload)
    assert_equal original_candidate_attributes, tracked_company_attributes(candidate.reload)
  end

  test "rejects limits above max limit" do
    error = assert_raises(ArgumentError) do
      AgentReviewBatchService.call(review_type: "description", limit: 26, max_limit: 25)
    end

    assert_match(/exceeds max_limit/, error.message)
  end

  test "rejects unknown review type" do
    error = assert_raises(ArgumentError) do
      AgentReviewBatchService.call(review_type: "unknown", limit: 1)
    end

    assert_match(/review_type must be one of/, error.message)
  end

  private

  def tracked_company_attributes(company)
    company.attributes.slice(*AgentReviewBatchService::TRACKED_COMPANY_FIELDS)
  end
end
