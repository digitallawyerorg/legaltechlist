require "test_helper"

class StatisticsRedirectsIntegrationTest < ActionDispatch::IntegrationTest
  test "orphan statistics pages redirect to statistics hub" do
    get "/statistics/exit_patterns"
    assert_redirected_to "/statistics"

    get "/statistics/founders_journey"
    assert_redirected_to "/statistics"

    get "/statistics/funding_stages"
    assert_redirected_to "/statistics/funding_by_category?dimension=venture_stage"
  end

  test "category evolution redirects to five year view" do
    get "/statistics/category_evolution"
    assert_redirected_to "/statistics/category_evolution_5_years"
  end

  test "legacy venture stage url redirects to funding page" do
    get "/statistics/venture_stage"
    assert_redirected_to "/statistics/funding_by_category?dimension=venture_stage"
  end

  test "legacy market focus and revenue model urls redirect to industry focus" do
    get "/statistics/target_client"
    assert_redirected_to "/statistics/category_evolution_5_years?dimension=market_focus"

    get "/statistics/business_model"
    assert_redirected_to "/statistics/category_evolution_5_years?dimension=revenue_model"
  end
end
