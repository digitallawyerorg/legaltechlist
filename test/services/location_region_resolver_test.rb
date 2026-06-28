require "test_helper"

class LocationRegionResolverTest < ActiveSupport::TestCase
  test "region_for_country maps known countries to innovation hub regions" do
    assert_equal LocationRegionResolver::UNITED_STATES, LocationRegionResolver.region_for_country("United States")
    assert_equal LocationRegionResolver::CANADA, LocationRegionResolver.region_for_country("Canada")
    assert_equal LocationRegionResolver::UK_IRELAND, LocationRegionResolver.region_for_country("United Kingdom")
    assert_equal LocationRegionResolver::UK_IRELAND, LocationRegionResolver.region_for_country("Ireland")
    assert_equal LocationRegionResolver::EUROPE, LocationRegionResolver.region_for_country("Germany")
    assert_equal LocationRegionResolver::EUROPE, LocationRegionResolver.region_for_country("Georgia")
    assert_equal LocationRegionResolver::EUROPE, LocationRegionResolver.region_for_country("Switzerland")
    assert_equal LocationRegionResolver::EUROPE, LocationRegionResolver.region_for_country("Netherlands")
    assert_equal LocationRegionResolver::EUROPE, LocationRegionResolver.region_for_country("Russia")
    assert_equal LocationRegionResolver::EUROPE, LocationRegionResolver.region_for_country("Turkey")
    assert_equal LocationRegionResolver::ASIA_PACIFIC, LocationRegionResolver.region_for_country("Australia")
    assert_equal LocationRegionResolver::ASIA_PACIFIC, LocationRegionResolver.region_for_country("Singapore")
    assert_equal LocationRegionResolver::LATIN_AMERICA, LocationRegionResolver.region_for_country("Brazil")
    assert_equal LocationRegionResolver::MIDDLE_EAST_AFRICA, LocationRegionResolver.region_for_country("Israel")
  end

  test "region_for_location resolves country first then maps region" do
    assert_equal LocationRegionResolver::UK_IRELAND, LocationRegionResolver.region_for_location("Knutsford, Cheshire")
    assert_equal LocationRegionResolver::EUROPE, LocationRegionResolver.region_for_location("Bochum, Nordrhein-Westfalen, Germany")
    assert_equal LocationRegionResolver::UNITED_STATES, LocationRegionResolver.region_for_location("San Francisco, California")
    assert_equal LocationRegionResolver::UNITED_STATES, LocationRegionResolver.region_for_location("Atlanta, Georgia")
    assert_equal LocationRegionResolver::EUROPE, LocationRegionResolver.region_for_location("Tbilisi, Georgia")
    assert_equal LocationRegionResolver::ASIA_PACIFIC, LocationRegionResolver.region_for_location("Hong Kong, Hong Kong Island")
  end

  test "region_for_country returns Other for unknown countries" do
    assert_equal LocationRegionResolver::OTHER, LocationRegionResolver.region_for_country("")
    assert_equal LocationRegionResolver::OTHER, LocationRegionResolver.region_for_country(nil)
  end
end
