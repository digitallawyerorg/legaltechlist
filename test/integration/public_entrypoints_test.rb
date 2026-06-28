require "test_helper"

class PublicEntrypointsTest < ActionDispatch::IntegrationTest
  test "public entry pages respond successfully" do
    get root_path
    assert_response :success

    get companies_path
    assert_response :success

    get statistics_path
    assert_response :success

    get rails_health_check_path
    assert_response :success
  end

  test "home page prioritizes category browsing before statistics" do
    get root_path

    assert_response :success
    assert_select ".home-title", "CodeX TechIndex"
    assert_select ".home-category-card"
    assert_operator @response.body.index(">By category</h2>"), :<, @response.body.index(">Statistics</h2>")
    assert_select ".stats-index-card", count: 9
    assert_select ".stats-hero-title", count: 0
    assert_select "h2.stats-chart-title", count: 0
  end

  test "statistics index shows nine curated cards" do
    get statistics_path

    assert_response :success
    assert_select ".stats-hero-title", text: "Statistics"
    assert_select ".stats-hero-subtitle", text: /Research insights into the legal technology landscape/
    assert_select "h2.stats-chart-title", count: 0
    assert_select ".stats-index-card", count: 9
    assert_select ".stats-index-card-vertical-bars", minimum: 1
    assert_select ".stats-index-card-country-bars", minimum: 1
    assert_select "svg path[stroke]", minimum: 1
    ["Ecosystem Growth", "Geographic Distribution", "Category Expansion", "Business Model", "Target Market", "Funding by Category", "Funding by Region", "AI in Legal Tech", "Technology Themes"].each do |title|
      assert_select ".stats-index-card-title", text: title
    end
    assert_select ".stats-index-card-desc", text: "Legal tech companies created over time."
    assert_select ".stats-index-card-meta", text: /From 2000 – \d{4}/
    assert_select ".stats-index-card-meta", text: /in Funding/
    assert_select ".stats-index-card-title", text: "Category Focus", count: 0
    assert_select ".stats-index-card-title", text: "Industry Focus", count: 0
    assert_select ".stats-index-card-title", text: "Venture Stage", count: 0
    assert_select ".stats-index-card-title", text: "Funding", count: 0
    assert_select ".stats-index-card-title", text: "Exit Patterns", count: 0
    assert_select ".stats-index-card-title", text: "Founder's Journey", count: 0
    assert_select ".stats-index-card-title", text: "Funding Stage Progression", count: 0
  end

  test "public navbar includes global company search" do
    get root_path

    assert_response :success
    assert_select ".public-nav-search input[name='query'][type='search'][data-nav-search-trigger]"
    assert_select ".overview-toggle", text: "Overview"
  end

  test "public navbar includes contribute link to new company page" do
    get root_path

    assert_response :success
    assert_select "a.public-nav-contribute[href='#{new_company_path}']", text: "Contribute"
  end

  test "public navbar overview dropdown reflects active page" do
    get about_path
    assert_response :success
    assert_select ".overview-toggle", text: "About"
    assert_select ".dropdown-item.active", text: "About"

    get statistics_path
    assert_response :success
    assert_select ".overview-toggle", text: "Statistics"

    get statistics_methodology_path
    assert_response :success
    assert_select ".overview-toggle", text: "Methodology"

    get companies_path
    assert_response :success
    assert_select ".overview-toggle", text: "Companies"
  end

  test "legacy innovation hubs url redirects to geographic distribution region view" do
    get "/statistics/innovation_hubs"

    assert_redirected_to "/statistics/country_distribution?view=region"
    assert_equal 301, response.status
  end

  test "legacy funding by region url redirects to unified funding page" do
    get "/statistics/funding_by_region"

    assert_redirected_to "/statistics/funding_by_category?dimension=region"
    assert_equal 301, response.status
  end

  test "admin login route is reachable" do
    get new_admin_user_session_path

    assert_response :success
  end
end
