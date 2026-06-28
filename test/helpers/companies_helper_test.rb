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
    assert_equal "ES", location_country_iso_code("Seville, Andalucia")
    assert_equal "US", location_country_iso_code("Tampa, Florida")
    assert_equal "IE", location_country_iso_code("Dublin, Dublin")
    assert_equal "IT", location_country_iso_code("Roma, Lazio")
    assert_equal "BE", location_country_iso_code("Ghent, Oost-Vlaanderen")
    assert_equal "GB", location_country_iso_code("Knutsford, Cheshire")
    assert_equal "US", location_country_iso_code("CHICAGO")
    assert_equal "GB", location_country_iso_code("London")
    assert_equal "DE", location_country_iso_code("Berlin")
  end

  test "format_location_with_flag keeps location text and prepends flag" do
    assert_equal "🇺🇸 San Francisco, CA", format_location_with_flag("San Francisco, CA")
    assert_equal "🇮🇪 Dublin, Dublin, Ireland", format_location_with_flag("Dublin, Dublin, Ireland")
    assert_equal "🇺🇸 USA", format_location_with_flag("United States")
    assert_equal "🇪🇸 Seville, Andalucia", format_location_with_flag("Seville, Andalucia")
    assert_equal "🇺🇸 Tampa, Florida", format_location_with_flag("Tampa, Florida")
  end

  test "company_filter_category_ids normalizes single and array params" do
    params[:category] = "3"
    assert_equal [3], company_filter_category_ids

    params[:category] = %w[1 2]
    assert_equal [1, 2], company_filter_category_ids
  end

  test "company_filter_statuses normalizes single and array params" do
    params[:status] = "Active"
    assert_equal ["active"], company_filter_statuses

    params[:status] = %w[active acquired]
    assert_equal %w[active acquired], company_filter_statuses
  end

  test "company_filter_category_label summarizes selection count" do
    category_counts = [{ id: 1, name: "Legal Research", count: 5 }]
    assert_equal "All categories", company_filter_category_label(category_counts, [])
    assert_equal "Legal Research", company_filter_category_label(category_counts, [1])
    assert_equal "2 categories", company_filter_category_label(category_counts, [1, 2])
  end

  test "company_filter_checkbox_checked when no selection means show all" do
    assert company_filter_category_checked?(1, [])
    assert company_filter_category_checked?(99, [])
    refute company_filter_category_checked?(2, [1])
    assert company_filter_category_checked?(2, [1, 2])

    assert company_filter_status_checked?("active", [])
    refute company_filter_status_checked?("active", ["acquired"])
    assert company_filter_status_checked?("active", %w[active acquired])
  end

  test "company_filter_master reflects all partial or none selection" do
    assert company_filter_master_checked?([], 5)
    assert company_filter_master_checked?([1, 2, 3, 4, 5], 5)
    refute company_filter_master_checked?([1, 2], 5)

    assert company_filter_master_indeterminate?([1, 2], 5)
    refute company_filter_master_indeterminate?([], 5)
    refute company_filter_master_indeterminate?([1, 2, 3, 4, 5], 5)
  end

  test "company_inactive detects inactive and closed statuses" do
    company = companies(:one)
    company.status = "active"
    refute company_inactive?(company)

    company.status = "inactive"
    assert company_inactive?(company)

    company.status = "Closed"
    assert company_inactive?(company)
  end

  test "company_legaltech_atlas_reference returns link hash only for valid atlas urls" do
    company = companies(:one)
    company.legaltech_atlas_url = nil
    assert_nil company_legaltech_atlas_reference(company)

    company.legaltech_atlas_url = "https://example.com/companies/clio"
    assert_nil company_legaltech_atlas_reference(company)

    company.legaltech_atlas_url = "https://legaltechatlas.com/companies/clio"
    reference = company_legaltech_atlas_reference(company)
    assert_equal "LegalTech Atlas", reference[:label]
    assert_equal "https://legaltechatlas.com/companies/clio", reference[:url]
    assert_equal "legaltechatlas.com", reference[:host]
  end
end
