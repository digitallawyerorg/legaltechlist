require "test_helper"

class MapRedirectTest < ActionDispatch::IntegrationTest
  test "/map permanently redirects to country distribution" do
    get "/map"
    assert_response :moved_permanently
    assert_redirected_to "/statistics/country_distribution"
  end
end
