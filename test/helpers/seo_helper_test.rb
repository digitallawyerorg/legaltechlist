require "test_helper"

class SeoHelperTest < ActionView::TestCase
  test "paginated_page_url omits page param for first page" do
    controller.request.path = "/companies"
    controller.request.env["QUERY_STRING"] = "page=2&category=1"
    controller.params = ActionController::Parameters.new(page: "2", category: "1")

    assert_equal "#{SeoHelper::DEFAULT_SITE_URL}/companies?category=1", paginated_page_url(1)
  end

  test "paginated_page_url keeps filters for later pages" do
    controller.request.path = "/companies"
    controller.request.env["QUERY_STRING"] = "category=1"
    controller.params = ActionController::Parameters.new(category: "1")

    assert_equal "#{SeoHelper::DEFAULT_SITE_URL}/companies?category=1&page=2", paginated_page_url(2)
  end
end
