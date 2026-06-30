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

  test "enqueue creates pending pipeline run" do
    run = CompanyDiscoveryService.enqueue(
      discovery_type: "country",
      country: "Canada",
      dry_run: true,
      admin_user: admin_users(:one)
    )

    assert_equal "pending", run.status
    assert_equal "company_discovery", run.run_type
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

  %w[year country funding_year].each do |discovery_type|
    test "#{discovery_type} dry run creates discovery pipeline run" do
      kwargs = {
        discovery_type: discovery_type,
        dry_run: true,
        search_service: StubSearchService,
        admin_user: admin_users(:one)
      }
      kwargs[:year] = "2024" if discovery_type == "year"
      kwargs[:country] = "Germany" if discovery_type == "country"
      kwargs[:funding_year] = "2024" if discovery_type == "funding_year"

      run = CompanyDiscoveryService.call(**kwargs)

      assert_equal "succeeded", run.status
      assert_equal discovery_type, run.details["discovery_type"]
      assert_equal 1, run.details["summary"]["absent_candidates"]
    end
  end

  test "year discovery requires year parameter" do
    assert_raises(ArgumentError, match: /YEAR is required/) do
      CompanyDiscoveryService.call(discovery_type: "year", dry_run: true, search_service: StubSearchService)
    end
  end

  test "country discovery requires country parameter" do
    assert_raises(ArgumentError, match: /COUNTRY is required/) do
      CompanyDiscoveryService.call(discovery_type: "country", dry_run: true, search_service: StubSearchService)
    end
  end

  test "funding_year discovery requires funding_year parameter" do
    assert_raises(ArgumentError, match: /FUNDING_YEAR is required/) do
      CompanyDiscoveryService.call(discovery_type: "funding_year", dry_run: true, search_service: StubSearchService)
    end
  end
end
