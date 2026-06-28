require "test_helper"

class ErrorPagesTest < ActionDispatch::IntegrationTest
  ERROR_PAGES = {
    "404.html" => {
      title: "Page not found | CodeX TechIndex",
      heading: "Page not found",
      code: "404"
    },
    "500.html" => {
      title: "Something went wrong | CodeX TechIndex",
      heading: "Something went wrong",
      code: "500"
    },
    "422.html" => {
      title: "Request rejected | CodeX TechIndex",
      heading: "Your request couldn't be processed",
      code: "422"
    },
    "403.html" => {
      title: "Access denied | CodeX TechIndex",
      heading: "Access denied",
      code: "403"
    }
  }.freeze

  ERROR_PAGES.each do |filename, expectations|
    test "#{filename} includes CodeX TechIndex branding and navigation links" do
      html = Rails.public_path.join(filename).read

      assert_includes html, expectations[:title]
      assert_includes html, expectations[:heading]
      assert_includes html, expectations[:code]
      assert_includes html, "CodeX TechIndex"
      assert_includes html, 'href="/"'
      assert_includes html, 'href="/companies"'
      assert_includes html, "#8c1515"
      assert_not_includes html, "application owner"
    end
  end

  test "missing route returns custom 404 when production-style exceptions are enabled" do
    with_production_error_pages do
      get "/this-route-definitely-does-not-exist-error-pages-test"

      assert_response :not_found
      assert_includes response.body, "Page not found"
      assert_includes response.body, "CodeX TechIndex"
      assert_includes response.body, 'href="/companies"'
    end
  end

  private

  def with_production_error_pages
    env_config = Rails.application.env_config
    previous = {
      show_exceptions: env_config["action_dispatch.show_exceptions"],
      show_detailed_exceptions: env_config["action_dispatch.show_detailed_exceptions"]
    }

    env_config["action_dispatch.show_exceptions"] = :all
    env_config["action_dispatch.show_detailed_exceptions"] = false
    yield
  ensure
    env_config["action_dispatch.show_exceptions"] = previous[:show_exceptions]
    env_config["action_dispatch.show_detailed_exceptions"] = previous[:show_detailed_exceptions]
  end
end
