require "test_helper"

class LogosControllerTest < ActionDispatch::IntegrationTest
  test "show returns stored logo with caching headers" do
    company = companies(:one)
    png_bytes = "\x89PNG\r\n\x1a\n".b
    CompanyLogo.create!(company: company, data: png_bytes, content_type: "image/png")

    get company_logo_path(company.id)

    assert_response :success
    assert_equal "image/png", response.media_type
    assert_equal png_bytes, response.body.b
    assert_equal "max-age=#{1.year.to_i}, public", response.headers["Cache-Control"]
    assert response.headers["ETag"].present?
  end

  test "show returns not found when company has no logo" do
    company = companies(:one)

    get company_logo_path(company.id)

    assert_response :not_found
  end

  test "show returns not found for unknown company id" do
    get company_logo_path(id: 0)

    assert_response :not_found
  end
end
