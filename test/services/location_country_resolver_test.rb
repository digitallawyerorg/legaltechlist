require "test_helper"

class LocationCountryResolverTest < ActiveSupport::TestCase
  test "iso_code_for resolves countries, states, and administrative regions" do
    assert_equal "GB", LocationCountryResolver.iso_code_for("London, England")
    assert_equal "ES", LocationCountryResolver.iso_code_for("Seville, Andalucia")
    assert_equal "US", LocationCountryResolver.iso_code_for("Tampa, Florida")
    assert_equal "IE", LocationCountryResolver.iso_code_for("Dublin, Dublin")
    assert_equal "IT", LocationCountryResolver.iso_code_for("Roma, Lazio")
    assert_equal "BE", LocationCountryResolver.iso_code_for("Ghent, Oost-Vlaanderen")
    assert_equal "GB", LocationCountryResolver.iso_code_for("Knutsford, Cheshire")
    assert_equal "US", LocationCountryResolver.iso_code_for("San Francisco, CA")
    assert_equal "US", LocationCountryResolver.iso_code_for("Miami, Florida, United States")
  end

  test "normalize_location_string appends inferred country" do
    assert_equal "Tampa, United States", LocationCountryResolver.normalize_location_string("Tampa, Florida")
    assert_equal "Seville, Spain", LocationCountryResolver.normalize_location_string("Seville, Andalucia")
    assert_equal "Dublin, Ireland", LocationCountryResolver.normalize_location_string("Dublin, Dublin")
    assert_nil LocationCountryResolver.normalize_location_string("London, England")
    assert_nil LocationCountryResolver.normalize_location_string("San Francisco, United States")
  end

  test "iso_code_for prefers explicit countries over administrative regions" do
    assert_equal "SC", LocationCountryResolver.iso_code_for("Victoria, Seychelles")
    assert_equal "HN", LocationCountryResolver.iso_code_for("New York, Honduras")
    assert_nil LocationCountryResolver.normalize_location_string("Victoria, Seychelles")
    assert_nil LocationCountryResolver.normalize_location_string("New York, Honduras")
  end

  test "country_name_for returns canonical country names" do
    assert_equal "United Kingdom", LocationCountryResolver.country_name_for("Knutsford, Cheshire")
    assert_equal "United States", LocationCountryResolver.country_name_for("Austin, Texas")
    assert_equal "Spain", LocationCountryResolver.country_name_for("Barcelona, Catalonia")
    assert_equal "North Macedonia", LocationCountryResolver.country_name_for("Gostivar, Macedonia")
  end
end
