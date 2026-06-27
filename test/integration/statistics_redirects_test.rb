require "test_helper"

class StatisticsRedirectsIntegrationTest < ActionDispatch::IntegrationTest
  test "orphan statistics pages redirect to statistics hub" do
    get "/statistics/exit_patterns"
    assert_redirected_to "/statistics"

    get "/statistics/founders_journey"
    assert_redirected_to "/statistics"

    get "/statistics/funding_stages"
    assert_redirected_to "/statistics"
  end

  test "category evolution redirects to five year view" do
    get "/statistics/category_evolution"
    assert_redirected_to "/statistics/category_evolution_5_years"
  end
end
