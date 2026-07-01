# frozen_string_literal: true

require "test_helper"

class LegacyUrlRedirectsTest < ActionDispatch::IntegrationTest
  include SeoHelper

  test "numeric company id redirects to slug url" do
    company = companies(:one)

    get company_path(company.id)

    assert_response :redirect
    assert_equal 301, response.status
    assert_match %r{/companies/#{company.slug}\z}, response.redirect_url.split("?").first
  end

  test "numeric category id redirects to slug url" do
    category = categories(:one)

    get category_path(category.id)

    assert_redirected_to category_path(category)
    assert_equal 301, response.status
  end

  test "single category query redirects to category facet url" do
    category = categories(:one)

    get companies_path(category: category.id)

    assert_redirected_to category_path(category)
    assert_equal 301, response.status
  end

  test "company show uses slug url" do
    company = companies(:one)

    get company_path(company)

    assert_response :success
    assert_select "link[rel='canonical'][href=?]", company_url(company)
  end

  test "category facet page renders filtered companies" do
    category = categories(:one)

    get category_path(category)

    assert_response :success
    assert_select "h1.company-index-title", "#{category.name} Companies"
    assert_select "link[rel='canonical'][href=?]", "#{site_url}#{category_path(category)}"
  end

  test "home category cards link to slug category paths" do
    get root_path

    assert_response :success
    assert_select "a.home-category-card[href='#{category_path(categories(:one))}']"
  end
end
