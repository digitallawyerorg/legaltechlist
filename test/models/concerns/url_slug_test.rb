# frozen_string_literal: true

require "test_helper"

class UrlSlugTest < ActiveSupport::TestCase
  test "slug_for_name normalizes names" do
    assert_equal "clio", Company.slug_for_name("Clio")
    assert_equal "kira-systems", Company.slug_for_name("Kira Systems")
  end

  test "find_by_slug_or_id resolves slug and numeric id" do
    company = companies(:one)

    assert_equal company, Company.find_by_slug_or_id(company.slug)
    assert_equal company, Company.find_by_slug_or_id(company.id)
    assert_nil Company.find_by_slug_or_id("missing-slug")
  end

  test "assign_slug_from_source adds numeric suffix for collisions" do
    existing = companies(:one)
    duplicate = Company.new(name: existing.name, slug: nil)

    duplicate.valid?

    assert_not_equal existing.slug, duplicate.slug
    assert_match(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/, duplicate.slug)
  end

  test "to_param returns slug when present" do
    company = companies(:one)

    assert_equal company.slug, company.to_param
  end
end
