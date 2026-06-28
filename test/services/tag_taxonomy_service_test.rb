require "test_helper"

class TagTaxonomyServiceTest < ActiveSupport::TestCase
  setup do
    TagTaxonomyService.reset_cache!
  end

  test "discoverable names exclude taxonomy-redundant tags" do
    discoverable = TagTaxonomyService.discoverable_canonical_names

    refute_includes discoverable, "saas"
    refute_includes discoverable, "law firms"
    refute_includes discoverable, "legal tech"
    refute_includes discoverable, "compliance"
    assert_includes discoverable, "artificial intelligence"
    assert_includes discoverable, "e-discovery"
  end

  test "redundant_with_taxonomy detects revenue model and target client overlap" do
    assert TagTaxonomyService.redundant_with_taxonomy?("SaaS")
    assert TagTaxonomyService.redundant_with_taxonomy?("Law Firms")
    assert TagTaxonomyService.redundant_with_taxonomy?("Contract Management")
    refute TagTaxonomyService.redundant_with_taxonomy?("generative ai")
  end

  test "filter_assignable keeps only discoverable canonical tags" do
    names = TagTaxonomyService.filter_assignable(["SaaS", "generative ai", "not-a-real-tag", "e-discovery"])

    assert_equal ["generative ai", "e-discovery"], names.sort
  end
end
