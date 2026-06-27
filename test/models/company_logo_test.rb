require "test_helper"

class CompanyLogoTest < ActiveSupport::TestCase
  test "belongs to company" do
    company = companies(:one)
    logo = CompanyLogo.create!(company: company, data: "\x89PNG\r\n\x1a\n".b, content_type: "image/png")

    assert_equal company, logo.company
    assert_equal logo, company.reload.company_logo
  end

  test "company logo is destroyed with company" do
    company = companies(:one)
    CompanyLogo.create!(company: company, data: "\x89PNG\r\n\x1a\n".b, content_type: "image/png")

    assert_difference "CompanyLogo.count", -1 do
      company.destroy
    end
  end
end
