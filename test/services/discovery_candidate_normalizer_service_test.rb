require "test_helper"

class DiscoveryCandidateNormalizerServiceTest < ActiveSupport::TestCase
  test "normalizes discovery hash through atlas dedup logic" do
    companies(:one).update!(name: "Existing Atlas Co", main_url: "https://existing-atlas.example.com", visible: true)

    normalized = DiscoveryCandidateNormalizerService.call(
      "name" => "Existing Atlas Co",
      "website" => "https://existing-atlas.example.com",
      "location" => "Boston, MA",
      "founded_date" => "2019",
      "description" => "Contract workflow software.",
      "why_discovered" => "Matches contract management category.",
      "discovery_type" => "category",
      "website_verified" => true
    )

    assert_equal "existing_or_possible_duplicate", normalized["status"]
    assert_equal "Existing Atlas Co", normalized["name"]
    assert_equal "llm_discovery", normalized["discovery_source"]
    assert_equal "category", normalized["discovery_type"]
    assert normalized["name_matches"].any? || normalized["domain_matches"].any?
  end

  test "marks absent candidates without index matches" do
    normalized = DiscoveryCandidateNormalizerService.call(
      "name" => "Brand New Discovery Co",
      "website" => "https://brand-new-discovery.example.com",
      "location" => "Austin, TX",
      "founded_date" => "2022",
      "description" => "Discovery-only legal workflow software.",
      "why_discovered" => "Not in exclusion list.",
      "discovery_type" => "category",
      "website_verified" => true
    )

    assert_equal "absent_candidate", normalized["status"]
    assert_empty normalized["name_matches"]
    assert_empty normalized["domain_matches"]
  end
end
