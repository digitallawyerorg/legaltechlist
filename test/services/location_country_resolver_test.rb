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

  test "format_for_display keeps explicit last-segment countries over city inference" do
    assert_equal "Victoria, Seychelles", LocationCountryResolver.format_for_display("Victoria, Seychelles")
    assert_equal "New York, Honduras", LocationCountryResolver.format_for_display("New York, Honduras")
  end

  test "country_name_for returns canonical country names" do
    assert_equal "United Kingdom", LocationCountryResolver.country_name_for("Knutsford, Cheshire")
    assert_equal "United States", LocationCountryResolver.country_name_for("Austin, Texas")
    assert_equal "United States", LocationCountryResolver.country_name_for("Atlanta, Georgia")
    assert_equal "Georgia", LocationCountryResolver.country_name_for("Tbilisi, Georgia")
    assert_equal "Spain", LocationCountryResolver.country_name_for("Barcelona, Catalonia")
    assert_equal "North Macedonia", LocationCountryResolver.country_name_for("Gostivar, Macedonia")
  end

  test "country_name_for resolves administrative regions to countries" do
    assert_equal "Hong Kong", LocationCountryResolver.country_name_for("Hong Kong, Hong Kong Island")
    assert_equal "Austria", LocationCountryResolver.country_name_for("Vienna, Wien")
    assert_equal "Denmark", LocationCountryResolver.country_name_for("Copenhagen, Hovedstaden")
    assert_equal "Switzerland", LocationCountryResolver.country_name_for("Rotkreuz, Zug")
    assert_equal "United Kingdom", LocationCountryResolver.country_name_for("Southbourne, Bournemouth")
  end

  test "country_name_for resolves duplicate city segments" do
    assert_equal "China", LocationCountryResolver.country_name_for("Beijing, Beijing")
    assert_equal "Norway", LocationCountryResolver.country_name_for("Oslo, Oslo")
    assert_equal "Brazil", LocationCountryResolver.country_name_for("Petrópolis, Rio de Janeiro")
    assert_equal "New Zealand", LocationCountryResolver.country_name_for("72 Tuam Street, Christchurch 8011")
  end

  test "normalize_country_name preserves country names over admin regions" do
    assert_equal "Georgia", LocationCountryResolver.normalize_country_name("Georgia")
    assert_equal "Ivory Coast", LocationCountryResolver.normalize_country_name("Côte d'Ivoire")
  end

  test "normalize_country_name collapses native-language and variant country names" do
    assert_equal "Switzerland", LocationCountryResolver.normalize_country_name("Schweiz")
    assert_equal "Switzerland", LocationCountryResolver.normalize_country_name("Suisse")
    assert_equal "Germany", LocationCountryResolver.normalize_country_name("Deutschland")
    assert_equal "Spain", LocationCountryResolver.normalize_country_name("España")
    assert_equal "Brazil", LocationCountryResolver.normalize_country_name("Brasil")
    assert_equal "Czech Republic", LocationCountryResolver.normalize_country_name("Czechia")
    assert_equal "South Korea", LocationCountryResolver.normalize_country_name("Korea")
  end

  test "normalize_country_name is case-insensitive for aliases and preserves canonical names" do
    assert_equal "Switzerland", LocationCountryResolver.normalize_country_name("schweiz")
    assert_equal "Switzerland", LocationCountryResolver.normalize_country_name("SCHWEIZ")
    assert_equal "Switzerland", LocationCountryResolver.normalize_country_name("Switzerland")
    assert_equal "United States", LocationCountryResolver.normalize_country_name("United States")
    assert_nil LocationCountryResolver.normalize_country_name(nil).presence
  end

  test "format_for_display keeps city and country for flag-friendly storage" do
    assert_equal "Newark, United States", LocationCountryResolver.format_for_display("Newark, Delaware, United States")
    assert_equal "Austin, United States", LocationCountryResolver.format_for_display("Austin, Texas, United States")
    assert_equal "Amsterdam, The Netherlands", LocationCountryResolver.format_for_display("Amsterdam, Noord-Holland, The Netherlands")
    assert_equal "London, United Kingdom", LocationCountryResolver.format_for_display("London, England, United Kingdom")
    assert_equal "Tampa, United States", LocationCountryResolver.format_for_display("Tampa, Florida")
    assert_equal "Vigo, Spain", LocationCountryResolver.format_for_display("Vigo, Galicia, Spain")
  end

  test "format_for_display resolves city-only locations for major legal-tech hubs" do
    assert_equal "London, United Kingdom", LocationCountryResolver.format_for_display("London")
    assert_equal "Berlin, Germany", LocationCountryResolver.format_for_display("Berlin")
    assert_equal "Paris, France", LocationCountryResolver.format_for_display("Paris")
    assert_equal "PARIS, France", LocationCountryResolver.format_for_display("PARIS")
    assert_equal "Amsterdam, Netherlands", LocationCountryResolver.format_for_display("Amsterdam")
    assert_equal "San Francisco, United States", LocationCountryResolver.format_for_display("San Francisco")
    assert_equal "CHICAGO, United States", LocationCountryResolver.format_for_display("CHICAGO")
    assert_equal "Mumbai, India", LocationCountryResolver.format_for_display("Mumbai")
    assert_equal "São Paulo, Brazil", LocationCountryResolver.format_for_display("São Paulo")
  end

  test "iso_code_for resolves city-only locations" do
    assert_equal "GB", LocationCountryResolver.iso_code_for("London")
    assert_equal "DE", LocationCountryResolver.iso_code_for("Berlin")
    assert_equal "FR", LocationCountryResolver.iso_code_for("Paris")
    assert_equal "NL", LocationCountryResolver.iso_code_for("Amsterdam")
    assert_equal "US", LocationCountryResolver.iso_code_for("Chicago")
    assert_equal "IN", LocationCountryResolver.iso_code_for("Mumbai")
  end

  test "format_for_display applies exact overrides for malformed location strings" do
    assert_equal "Toronto, Canada", LocationCountryResolver.format_for_display("Toronto CANADA")
    assert_equal "Bellevue, United States", LocationCountryResolver.format_for_display("Bellevue WA")
    assert_equal "Paris, France", LocationCountryResolver.format_for_display("Paris 75001")
    assert_equal "Dubai, United Arab Emirates", LocationCountryResolver.format_for_display("Sheikh Zayed Road Dubai")
  end

  test "format_for_display leaves ambiguous or placeholder locations unchanged" do
    assert_equal "na", LocationCountryResolver.format_for_display("na")
    assert_equal "No location yet", LocationCountryResolver.format_for_display("No location yet")
    assert_equal "Halifax", LocationCountryResolver.format_for_display("Halifax")
    assert_equal "East London", LocationCountryResolver.format_for_display("East London")
    assert_equal "Global", LocationCountryResolver.format_for_display("Global")
  end

  test "parse returns structured country and city" do
    assert_equal({ country: "United States", city: "San Francisco" }, LocationCountryResolver.parse("San Francisco, CA"))
    assert_equal({ country: "United Kingdom", city: "London" }, LocationCountryResolver.parse("London, England"))
    assert_equal({ country: "United States", city: nil }, LocationCountryResolver.parse("United States"))
    assert_equal({ country: nil, city: nil }, LocationCountryResolver.parse("Location unknown"))
    assert_equal({ country: "Spain", city: "Seville" }, LocationCountryResolver.parse("Seville, Andalucia"))
  end

  test "city_name_for returns city when parseable and nil for country-only strings" do
    assert_equal "Berlin", LocationCountryResolver.city_name_for("Berlin")
    assert_equal "San Francisco", LocationCountryResolver.city_name_for("San Francisco, CA")
    assert_nil LocationCountryResolver.city_name_for("United States")
    assert_nil LocationCountryResolver.city_name_for("Location unknown")
  end

  test "placeholder_location detects known placeholders" do
    assert LocationCountryResolver.placeholder_location?("Global")
    assert LocationCountryResolver.placeholder_location?("Location unknown")
    refute LocationCountryResolver.placeholder_location?("London")
  end
end
