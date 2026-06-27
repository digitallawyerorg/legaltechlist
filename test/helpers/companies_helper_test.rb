require 'test_helper'

class CompaniesHelperTest < ActionView::TestCase
  test "country_flag_emoji returns regional indicator symbols" do
    assert_equal "🇺🇸", country_flag_emoji("US")
    assert_equal "🇬🇧", country_flag_emoji("GB")
  end

  test "location_country_iso_code detects us states and countries" do
    assert_equal "US", location_country_iso_code("San Francisco, CA")
    assert_equal "IE", location_country_iso_code("Dublin, Dublin, Ireland")
    assert_equal "IN", location_country_iso_code("Gurgaon, Haryana, India")
    assert_equal "US", location_country_iso_code("United States")
    assert_nil location_country_iso_code("CHICAGO")
  end

  test "format_location_with_flag keeps location text and prepends flag" do
    assert_equal "🇺🇸 San Francisco, CA", format_location_with_flag("San Francisco, CA")
    assert_equal "🇮🇪 Dublin, Dublin, Ireland", format_location_with_flag("Dublin, Dublin, Ireland")
    assert_equal "🇺🇸 USA", format_location_with_flag("United States")
  end
end
