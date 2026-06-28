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
    assert_select "title", text: "About"
    assert_select "meta[name=?][content*='Stanford CodeX']", "description"
  end

  test "should get statistics" do
    get :statistics
    assert_response :success
    assert_select ".stats-index-card", count: 8
  end

  test "should get business_model" do
    get :business_model
    assert_response :success
  end

  test "should get country_distribution with geo chart" do
    get :country_distribution
    assert_response :success
    assert_includes @response.body, "country-distribution-chart"
    assert_includes @response.body, "Chartkick"
    assert_includes @response.body, "GeoChart"
    assert_includes @response.body, "gstatic.com/charts/loader.js"
  end

  test "should get total_companies cumulative view" do
    get :total_companies
    assert_response :success
  end

  test "should get total_companies annual view" do
    get :total_companies, params: { view: "annual" }
    assert_response :success
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
    assert_includes @response.body, "Company data dictionary"
    assert_includes @response.body, "Primary categories (12)"
    assert_includes @response.body, "taxonomy v2"
    assert_not_includes @response.body, "Visibility rules"
  end

  test "statistics pages include methodology partial" do
    get :target_client
    assert_response :success
    assert_includes @response.body, "stats-methodology"
  end

  test "funding page includes disclosed funding caveat" do
    get :funding_by_category
    assert_response :success
    assert_includes @response.body, "disclosed venture capital"
  end

  test "country distribution includes geo navigation" do
    get :country_distribution
    assert_response :success
    assert_includes @response.body, "Innovation hubs"
    assert_includes @response.body, "stats-geo-nav"
  end

  test "should get category_evolution_5_years with cumulative line chart" do
    get :category_evolution_5_years
    assert_response :success
    assert_includes @response.body, "category-evolution-chart"
    assert_includes @response.body, "LineChart"
    assert_includes @response.body, "Top 8 categories"
  end

  test "should get category_evolution_5_years with all categories" do
    get :category_evolution_5_years, params: { categories: "all" }
    assert_response :success
    assert_includes @response.body, "All categories"
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
