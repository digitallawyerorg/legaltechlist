require "test_helper"

class SubmissionDuplicateDetectorTest < ActiveSupport::TestCase
  setup do
    @previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache.lookup_store(:memory_store)
    Rails.cache.clear
  end

  teardown do
    Rails.cache = @previous_cache
  end

  test "detects repeated fingerprints within the window" do
    fingerprint = "reviewer@example.com|1|incorrect_details|founded year should be 2014"

    assert_not SubmissionDuplicateDetector.duplicate?(fingerprint: fingerprint)
    SubmissionDuplicateDetector.record!(fingerprint: fingerprint)
    assert SubmissionDuplicateDetector.duplicate?(fingerprint: fingerprint)
  end
end
