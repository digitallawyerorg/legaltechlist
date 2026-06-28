require 'test_helper'

class StaticPagesControllerTest < ActionController::TestCase
  test "should get home" do
    get :home
    assert_response :success
    assert_select "title", text: "Legal Tech Company Database"
    assert_select "meta[name=?][content*='curated ecosystem data']", "description"
  end

  test "should get about" do
    get :about
    assert_response :success
    assert_select "title", text: /About/
    assert_select "meta[name=?][content*='Stanford CodeX']", "description"
    assert_includes @response.body, "About the CodeX TechIndex"
    assert_includes @response.body, "Contributors"
    assert_includes @response.body, "Contributor, Code = Law Participant"
    assert_not_includes @response.body, 'src=""'
  end

  test "should get statistics" do
    get :statistics
    assert_response :success
    assert_select ".stats-index-card", count: 10
  end

  test "should get business_model" do
    get :business_model
    assert_response :success
  end

  test "country distribution renders map chart only" do
    get :country_distribution
    assert_response :success
    assert_includes @response.body, "country-distribution-chart"
    assert_includes @response.body, "drawCountryGeoChart"
    assert_includes @response.body, "country-distribution-chart-data"
    assert_includes @response.body, "gstatic.com/charts/loader.js"
    assert_select "h1.stats-chart-title", text: "Companies by Country"
    assert_not_includes @response.body, "drawRegionCountrySunburstChart"
  end

  test "country distribution redirects legacy regions view" do
    get :country_distribution, params: { view: "regions" }
    assert_redirected_to statistics_companies_by_region_path
  end

  test "companies by region renders sankey chart" do
    get :companies_by_region
    assert_response :success
    assert_includes @response.body, "companies-by-region-chart"
    assert_includes @response.body, "companies-by-region-data"
    assert_includes @response.body, "drawRegionCountrySankeyChart"
    assert_includes @response.body, "type: \"sankey\""
    assert_includes @response.body, "echarts@5.5.1/dist/echarts.min.js"
    assert_select "h1.stats-chart-title", text: "Companies by Region"
    assert assigns(:region_sankey_data).present?
    assert_equal "All companies", assigns(:region_sankey_data)[:nodes].first[:name]
    assert assigns(:region_sankey_data)[:links].present?
    assert assigns(:region_sankey_data)[:links].any? { |link| link[:source] == "All companies" }
  end

  test "funding by region renders funding sunburst chart" do
    get :funding_by_region
    assert_response :success
    assert_includes @response.body, "funding-by-region-chart"
    assert_includes @response.body, "funding-by-region-data"
    assert_select "h1.stats-chart-title", text: "Disclosed Funding by Region"
    assert_equal "Disclosed funding", assigns(:region_sunburst_tree)[:name]
  end

  test "should get total_companies cumulative view" do
    get :total_companies
    assert_response :success
    assert_select "h1.stats-chart-title", text: "Total Companies"
    assert_select ".stats-segment-control .stats-segment.is-active", text: "Cumulative"
    assert_select ".stats-chart-nav .stats-chart-nav-prev .stats-chart-nav-title", text: "Revenue Model Insights"
    assert_select ".stats-chart-nav .stats-chart-nav-next .stats-chart-nav-title", text: "Companies by Country"
    assert_select ".stats-page-back", count: 0
  end

  test "total_companies all time redirects to default range" do
    get :total_companies_all_time
    assert_redirected_to statistics_total_companies_path

    get :total_companies_all_time, params: { view: "annual" }
    assert_redirected_to statistics_total_companies_path(view: "annual")
  end

  test "should get total_companies annual view" do
    get :total_companies, params: { view: "annual" }
    assert_response :success
    assert_select ".stats-segment-control .stats-segment.is-active", text: "By Year"
  end

  test "companies_founded redirects to unified growth page" do
    get :companies_founded
    assert_redirected_to statistics_total_companies_path(view: "annual")
  end

  test "companies_founded csv export still works" do
    get :companies_founded, params: { format: :csv }
    assert_response :success
    assert_equal "text/csv", @response.media_type
  end

  test "extract_country normalizes country aliases and administrative regions" do
    examples = {
      "San Francisco, CA" => "United States",
      "San Francisco,  California" => "United States",
      "London,  England" => "United Kingdom",
      "Toronto,  Ontario" => "Canada",
      "Mumbai,  Maharashtra" => "India",
      "Sydney,  New South Wales" => "Australia",
      "Tallinn,  Harjumaa" => "Estonia",
      "Milano,  Lombardia" => "Italy",
      "Roma,  Lazio" => "Italy",
      "Amsterdam,  Noord-Holland" => "Netherlands",
      "Cambridge,  Cambridgeshire" => "United Kingdom",
      "Edinburgh,  Edinburgh" => "United Kingdom",
      "Sheridan,  Wyoming" => "United States",
      "Noida,  Uttar Pradesh" => "India",
      "Ahmedabad,  Gujarat" => "India",
      "Barcelona,  Catalonia" => "Spain",
      "Singapore,  Central Region" => "Singapore",
      "Dubai,  Dubai" => "United Arab Emirates",
      "Gent,  Oost-Vlaanderen" => "Belgium",
      "Tel Aviv,  Tel Aviv" => "Israel",
      "Islamabad,  Islamabad" => "Pakistan",
      "Limasol,  Limassol" => "Cyprus",
      "Cape Town,  NA - South Africa" => "South Africa",
      "San Francisco, United States1" => "United States",
      "New York City, United States2" => "United States",
      "London, United Kingdom1" => "United Kingdom",
      "Wiesbaden, Germany1" => "Germany",
      "Taipei, Taiwan1" => "Taiwan",
      "Hong Kong China" => "Hong Kong"
    }

    examples.each do |location, country|
      assert_equal country, @controller.send(:extract_country, location), "Expected #{location.inspect} to normalize to #{country.inspect}"
    end
  end

  test "methodology page renders" do
    get :methodology
    assert_response :success
    assert_includes @response.body, "Data Methodology"
    assert_includes @response.body, "Company profiles"
    assert_includes @response.body, "Company profile fields"
    assert_includes @response.body, "Citations"
    assert_includes @response.body, "data-citation-copy"
    assert_includes @response.body, "[1]"
    assert_includes @response.body, "CodeX TechIndex"
    assert_includes @response.body, "Primary categories (12)"
    assert_includes @response.body, "12 primary functional categories"
    assert_not_includes @response.body, "Visibility rules"
    assert_not_includes @response.body, "Situation"
  end

  test "statistics pages include methodology partial" do
    get :target_client
    assert_response :success
    assert_includes @response.body, "stats-methodology"
  end

  test "should get category_evolution_5_years with cumulative line chart" do
    get :category_evolution_5_years
    assert_response :success
    assert_includes @response.body, "category-evolution-chart"
    assert_includes @response.body, "LineChart"
    assert_select "h1.stats-chart-title", text: "Companies by Category (Cumulative)"
    assert_select ".stats-category-filter-checkbox", minimum: 1
    assert_equal assigns(:table_data).size, assigns(:chart_series).size
  end

  test "should get tag_distribution with column chart" do
    get :tag_distribution
    assert_response :success
    assert_includes @response.body, "tag-distribution-chart"
    assert_includes @response.body, "ColumnChart"
    assert_includes @response.body, "chart.js"
  end

  test "statistics pages include turbo chart bootstrap" do
    get :tag_distribution
    assert_response :success
    assert_includes @response.body, "turbo.min.js"
    assert_includes @response.body, "chartkick:load"
    assert_includes @response.body, 'data-turbo-track="reload"'
  end

end
