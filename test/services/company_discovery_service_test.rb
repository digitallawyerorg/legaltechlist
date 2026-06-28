require "test_helper"

class CompanyDiscoveryServiceTest < ActiveSupport::TestCase
  StubSearchService = Class.new do
    def self.call(**kwargs)
      existing = Company.find_by(name: "Test Company One") || Company.first
      {
        "mode" => "stub",
        "discovery_type" => kwargs[:discovery_type],
        "query" => "stub query",
        "companies" => [
          {
            "name" => "Fresh Discovery Co",
            "website" => "https://fresh-discovery.example",
            "location" => "Boston, MA",
            "founded_date" => "2023",
            "description" => "Provides contract automation for legal teams.",
            "why_discovered" => "Matches the requested category.",
            "discovery_type" => kwargs[:discovery_type],
            "discovery_query" => "stub query",
            "website_verified" => true
          },
          {
            "name" => existing.name,
            "website" => existing.main_url,
            "location" => existing.location,
            "founded_date" => existing.founded_date.to_s,
            "description" => "Already indexed duplicate.",
            "why_discovered" => "Should match existing index entry.",
            "discovery_type" => kwargs[:discovery_type],
            "discovery_query" => "stub query",
            "website_verified" => true
          }
        ],
        "raw_search_call_count" => 1,
        "generated_at" => Time.current.utc.iso8601
      }
    end
  end

  test "dry run creates discovery pipeline run with absent and duplicate candidates" do
    assert_difference "PipelineRun.count", 1 do
      run = CompanyDiscoveryService.call(
        discovery_type: "category",
        category: categories(:one).name,
        dry_run: true,
        search_service: StubSearchService,
        admin_user: admin_users(:one)
      )

      assert_equal "company_discovery", run.run_type
      assert_equal "succeeded", run.status
      assert_equal true, run.details["dry_run"]
      assert_equal 1, run.details["summary"]["absent_candidates"]
      assert_equal 1, run.details["summary"]["existing_or_possible_duplicates"]
      assert_equal [], run.details["proposal_results"]
    end
  end

  test "queue proposals requires dry run false" do
    assert_raises(ArgumentError) do
      CompanyDiscoveryService.call(
        discovery_type: "category",
        category: categories(:one).name,
        dry_run: true,
        queue_proposals: true,
        search_service: StubSearchService,
        admin_user: admin_users(:one)
      )
    end
  end
end
