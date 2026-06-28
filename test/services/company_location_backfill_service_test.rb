require "test_helper"

class CompanyLocationBackfillServiceTest < ActiveSupport::TestCase
  setup do
    @company = companies(:one)
  end

  test "backfills country and city from location in dry run" do
    @company.update_columns(location: "San Francisco, CA", country: nil, city: nil)

    result = CompanyLocationBackfillService.call(company: @company.reload, dry_run: true)

    assert_equal "would_apply", result["action"]
    assert_equal "United States", result["country"]
    assert_equal "San Francisco", result["city"]
    assert_nil @company.reload.country
  end

  test "writes country and city when dry run is disabled" do
    @company.update_columns(location: "London, England", country: nil, city: nil)

    result = CompanyLocationBackfillService.call(company: @company.reload, dry_run: false)

    assert_equal "applied", result["action"]
    assert_equal "United Kingdom", @company.reload.country
    assert_equal "London", @company.city
  end

  test "skips placeholder locations" do
    @company.update_columns(location: "Location unknown", country: nil, city: nil)

    result = CompanyLocationBackfillService.call(company: @company.reload, dry_run: false)

    assert_equal "skipped_placeholder_location", result["action"]
    assert_nil @company.reload.country
  end

  test "skips already structured companies unless overwrite is enabled" do
    @company.update_columns(location: "Paris, France", country: "France", city: "Paris")

    result = CompanyLocationBackfillService.call(company: @company.reload, dry_run: false)

    assert_equal "skipped_already_structured", result["action"]
  end

  test "country-only locations backfill without city" do
    @company.update_columns(location: "United States", country: nil, city: nil)

    result = CompanyLocationBackfillService.call(company: @company.reload, dry_run: false)

    assert_equal "applied", result["action"]
    assert_equal "United States", @company.reload.country
    assert_nil @company.city
  end
end
