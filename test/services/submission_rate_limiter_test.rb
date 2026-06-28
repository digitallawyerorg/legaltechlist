require "test_helper"

class SubmissionRateLimiterTest < ActiveSupport::TestCase
  setup do
    @previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache.lookup_store(:memory_store)
    Rails.cache.clear
  end

  teardown do
    Rails.cache = @previous_cache
  end

  test "allows submissions under ip limits" do
    limiter = SubmissionRateLimiter.new(ip: "203.0.113.1", action: "company_contribution")

    assert limiter.allow?
    limiter.record!
    assert limiter.allow?
  end

  test "blocks submissions over hourly ip limit" do
    SubmissionRateLimiter::HOURLY_LIMIT.times do
      SubmissionRateLimiter.new(ip: "203.0.113.2", action: "company_contribution").record!
    end

    limiter = SubmissionRateLimiter.new(ip: "203.0.113.2", action: "company_contribution")
    assert_not limiter.allow?
  end

  test "blocks submissions over hourly email limit" do
    SubmissionRateLimiter::EMAIL_HOURLY_LIMIT.times do
      SubmissionRateLimiter.new(ip: "203.0.113.3", action: "company_suggestion", email: "abuser@example.com").record!
    end

    limiter = SubmissionRateLimiter.new(ip: "203.0.113.99", action: "company_suggestion", email: "abuser@example.com")
    assert_not limiter.allow?
  end
end
