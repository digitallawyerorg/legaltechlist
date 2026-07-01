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
    category_counts = [{ id: 1, name: "Knowledge & Research", count: 5 }]
    assert_equal "All categories", company_filter_category_label(category_counts, [])
    assert_equal "Knowledge & Research", company_filter_category_label(category_counts, [1])
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
    assert_equal "legaltechatlas.com/companies/clio", reference[:host]
  end

  test "company_google_search_reference builds a google search url for the company name" do
    company = companies(:one)
    company.name = "Legal.io"

    reference = company_google_search_reference(company)

    assert_equal "Google", reference[:label]
    assert_equal "https://www.google.com/search?q=can+you+tell+me+more+about+Legal.io", reference[:url]
    assert_equal "google.com", reference[:host]
  end

  test "company_reddit_search_reference builds a reddit search url for the company name" do
    company = companies(:one)
    company.name = "Legal.io"

    reference = company_reddit_search_reference(company)

    assert_equal "Reddit", reference[:label]
    assert_equal "https://www.reddit.com/search/?q=%22Legal.io%22", reference[:url]
    assert_equal "reddit.com", reference[:host]
  end

  test "company_reference_url_label returns a schemeless url for display" do
    assert_equal "legal.io/about", company_reference_url_label("https://legal.io/about")
    assert_equal "legal.io", company_reference_url_label("legal.io")
    assert_equal "www.legal.io", company_reference_url_label("https://www.legal.io/")
    assert_nil company_reference_url_label("")
  end

  test "company_reference_link_url normalizes urls used in reference links" do
    assert_equal "https://legal.io", company_reference_link_url("legal.io")
    assert_equal "https://legal.io/about", company_reference_link_url("https://legal.io/about")
  end

  test "company_citation_entries returns bluebook apa and bibtex formats" do
    company = companies(:one)
    company.name = "Legal.io"
    accessed_on = Date.new(2026, 7, 1)

    entries = company_citation_entries(company, accessed_on: accessed_on)

    assert_equal %w[Bluebook APA BibTeX], entries.map { |entry| entry[:label] }
    assert_includes entries[0][:citation], "Stanford Ctr. for Legal Informatics (CodeX), CodeX TechIndex: Legal.io"
    assert_includes entries[0][:citation], "(last visited July 1, 2026)."
    assert_includes entries[1][:citation], "Stanford Center for Legal Informatics (CodeX). (n.d.). Legal.io. In CodeX TechIndex."
    assert_includes entries[1][:citation], "Retrieved July 1, 2026, from"
    assert_includes entries[2][:citation], "@misc{techindex_company_#{company.id},"
    assert_includes entries[2][:citation], "title = {{CodeX TechIndex: Legal.io}}"
    assert_includes entries[2][:citation], "urldate = {2026-07-01}"
    assert entries[2][:monospace]
  end

  test "company_bibtex_citation braces company names with special characters" do
    company = companies(:one)
    company.name = "Smith & Jones"
    accessed_on = Date.new(2026, 7, 1)

    citation = company_bibtex_citation(company, accessed_on: accessed_on)

    assert_includes citation, "title = {{CodeX TechIndex: Smith & Jones}}"
  end
end
