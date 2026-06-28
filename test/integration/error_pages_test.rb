require "test_helper"

class ErrorPagesTest < ActionDispatch::IntegrationTest
  ERROR_PAGES = {
    not_found: {
      path: "/404",
      status: :not_found,
      title: "Page not found | CodeX TechIndex",
      heading: "Page not found",
      code: "404"
    },
    unprocessable_entity: {
      path: "/422",
      status: :unprocessable_entity,
      title: "Request rejected | CodeX TechIndex",
      heading: "Your request couldn",
      code: "422"
    },
    forbidden: {
      path: "/403",
      status: :forbidden,
      title: "Access denied | CodeX TechIndex",
      heading: "Access denied",
      code: "403"
    },
    internal_server_error: {
      path: "/500",
      status: :internal_server_error,
      title: "Something went wrong | CodeX TechIndex",
      heading: "Something went wrong",
      code: "500"
    }
  }.freeze

  ERROR_PAGES.each do |action, expectations|
    test "#{action} renders with site navigation and branded content" do
      get expectations[:path]

      assert_response expectations[:status]
      assert_includes response.body, expectations[:title]
      assert_includes response.body, expectations[:heading]
      assert_includes response.body, expectations[:code]
      assert_includes response.body, "CodeX TechIndex"
      assert_includes response.body, 'href="/companies"'
      assert_includes response.body, "navbar"
      assert_includes response.body, "public-footer"
      assert_includes response.body, 'content="noindex"'
      assert_includes response.body, "error-page-card"
      assert_includes response.body, "error-page-action-primary"
      assert_includes response.body, "error-page-action-secondary"
      assert_includes response.body, ".error-page-actions"
      assert_not_includes response.body, "application owner"
    end
  end

  test "missing route returns custom 404 when production-style exceptions are enabled" do
    with_production_error_pages do
      get "/this-route-definitely-does-not-exist-error-pages-test"

      assert_response :not_found
      assert_includes response.body, "Page not found"
      assert_includes response.body, "CodeX TechIndex"
      assert_includes response.body, 'href="/companies"'
      assert_includes response.body, "navbar"
    end
  end

  test "static 500 fallback remains available for catastrophic failures" do
    html = Rails.public_path.join("fallback-500.html").read

    assert_includes html, "Something went wrong"
    assert_includes html, "CodeX TechIndex"
    assert_includes html, 'href="/companies"'
    assert_not_includes html, "navbar"
  end

  private

  def with_production_error_pages
    env_config = Rails.application.env_config
    show_exceptions_middleware = find_show_exceptions_middleware(Rails.application)
    previous = {
      show_exceptions: env_config["action_dispatch.show_exceptions"],
      show_detailed_exceptions: env_config["action_dispatch.show_detailed_exceptions"],
      consider_all_requests_local: Rails.application.config.consider_all_requests_local,
      exceptions_app: show_exceptions_middleware.instance_variable_get(:@exceptions_app)
    }

    Rails.application.config.consider_all_requests_local = false
    env_config["action_dispatch.show_exceptions"] = :all
    env_config["action_dispatch.show_detailed_exceptions"] = false
    show_exceptions_middleware.instance_variable_set(:@exceptions_app, Rails.application.routes)
    yield
  ensure
    Rails.application.config.consider_all_requests_local = previous[:consider_all_requests_local]
    env_config["action_dispatch.show_exceptions"] = previous[:show_exceptions]
    env_config["action_dispatch.show_detailed_exceptions"] = previous[:show_detailed_exceptions]
    show_exceptions_middleware.instance_variable_set(:@exceptions_app, previous[:exceptions_app])
  end

  def find_show_exceptions_middleware(app)
    return app if app.is_a?(ActionDispatch::ShowExceptions)

    inner = app.instance_variable_get(:@app)
    return nil unless inner

    find_show_exceptions_middleware(inner)
  end
end
