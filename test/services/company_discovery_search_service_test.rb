require "test_helper"

class CompanyDiscoverySearchServiceTest < ActiveSupport::TestCase
  StubSearchClient = lambda do |prompt|
    {
      content: {
        "companies" => [
          {
            "name" => "Funded Legal Co",
            "website" => "https://funded-legal.example",
            "location" => "Berlin, Germany",
            "founded_date" => "2021",
            "description" => "Contract review automation for legal teams.",
            "why_discovered" => "Raised Series A in 2024.",
            "funding_round_year" => "2024",
            "funding_round_type" => "Series A",
            "funding_amount_hint" => "$12M"
          }
        ]
      }.to_json,
      search_urls: ["https://funded-legal.example/about"],
      raw_search_call_count: 1
    }
  end

  test "funding_year discovery includes funding hints in company payload" do
    result = CompanyDiscoverySearchService.call(
      discovery_type: "funding_year",
      context: { funding_year: "2024" },
      exclusion_list: { "names" => [], "domains" => [] },
      limit: 5,
      search_client: StubSearchClient
    )

    company = result["companies"].first
    assert_equal "funding_year", company["discovery_type"]
    assert_equal "2024", company["funding_round_year"]
    assert_equal "Series A", company["funding_round_type"]
    assert_equal "$12M", company["funding_amount_hint"]
    assert_equal true, company["website_verified"]
  end

  test "year discovery builds founded-year query" do
    result = CompanyDiscoverySearchService.call(
      discovery_type: "year",
      context: { year: "2024" },
      exclusion_list: { "names" => [], "domains" => [] },
      limit: 5,
      search_client: StubSearchClient
    )

    assert_match(/founded in 2024/, result["query"])
  end

  test "country discovery builds country query" do
    result = CompanyDiscoverySearchService.call(
      discovery_type: "country",
      context: { country: "Germany" },
      exclusion_list: { "names" => [], "domains" => [] },
      limit: 5,
      search_client: StubSearchClient
    )

    assert_match(/headquartered in Germany/, result["query"])
  end

  test "retries once when search returns zero companies" do
    calls = 0
    retry_client = lambda do |_prompt|
      calls += 1
      if calls == 1
        { content: { "companies" => [] }.to_json, search_urls: [], raw_search_call_count: 1 }
      else
        StubSearchClient.call(_prompt)
      end
    end

    result = CompanyDiscoverySearchService.call(
      discovery_type: "year",
      context: { year: "2024" },
      exclusion_list: { "names" => [], "domains" => [] },
      limit: 5,
      search_client: retry_client
    )

    assert_equal 2, calls
    assert_equal true, result["empty_result_retry"]
    assert_equal 1, result["companies"].size
  end
end
