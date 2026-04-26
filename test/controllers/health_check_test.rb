require 'test_helper'

class HealthCheckTest < ActionDispatch::IntegrationTest
  test "health check responds successfully" do
    get rails_health_check_path

    assert_response :success
    assert_equal "OK", response.body
  end
end
