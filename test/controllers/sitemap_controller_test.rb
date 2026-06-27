require "test_helper"

class SitemapControllerTest < ActionController::TestCase
  test "sitemap returns xml with key urls" do
    get :index, format: :xml
    assert_response :success
    assert_equal "application/xml", @response.media_type
    assert_includes @response.body, "<loc>"
    assert_includes @response.body, "https://techindex.law.stanford.edu/statistics</loc>"
    assert_includes @response.body, "https://techindex.law.stanford.edu/companies</loc>"
  end
end
