require "test_helper"

class LogoFetcherServiceTest < ActiveSupport::TestCase
  test "dry run reports verified missing logos without updating records" do
    company = companies(:one)
    company.update!(logo_url: nil)

    result = LogoFetcherService.backfill_missing_logos(scope: Company.where(id: company.id), dry_run: true, limit: nil, provider: :duckduckgo, verifier: ->(_url) { true }, logger: nil)

    assert_equal 1, result.checked
    assert_equal 1, result.updated
    assert_nil company.reload.logo_url
    assert_equal "example.com", result.examples.first[:domain]
    assert_equal "https://icons.duckduckgo.com/ip3/example.com.ico", result.examples.first[:logo_url]
  end

  test "updates missing logos when not a dry run" do
    company = companies(:one)
    company.update!(logo_url: nil)

    result = LogoFetcherService.backfill_missing_logos(scope: Company.where(id: company.id), dry_run: false, limit: nil, provider: :duckduckgo, verifier: ->(_url) { true }, logger: nil)

    assert_equal 1, result.updated
    assert_equal "https://icons.duckduckgo.com/ip3/example.com.ico", company.reload.logo_url
  end

  test "skips companies with existing non-placeholder logos" do
    company = companies(:one)
    company.update!(logo_url: "https://cdn.example.com/logo.png")

    result = LogoFetcherService.backfill_missing_logos(scope: Company.where(id: company.id), dry_run: false, limit: nil, provider: :duckduckgo, verifier: ->(_url) { true }, logger: nil)

    assert_equal 1, result.checked
    assert_equal 1, result.skipped_existing
    assert_equal "https://cdn.example.com/logo.png", company.reload.logo_url
  end

  test "replaces placeholder logos" do
    company = companies(:one)
    company.update!(logo_url: "https://placehold.co/64x64?text=T")

    result = LogoFetcherService.backfill_missing_logos(scope: Company.where(id: company.id), dry_run: false, limit: nil, provider: :duckduckgo, verifier: ->(_url) { true }, logger: nil)

    assert_equal 1, result.updated
    assert_equal "https://icons.duckduckgo.com/ip3/example.com.ico", company.reload.logo_url
  end

  test "skips missing logos without a canonical domain" do
    company = companies(:one)
    company.update!(logo_url: nil, main_url: "Unknown")

    result = LogoFetcherService.backfill_missing_logos(scope: Company.where(id: company.id), dry_run: false, limit: nil, provider: :duckduckgo, verifier: ->(_url) { true }, logger: nil)

    assert_equal 1, result.skipped_no_domain
    assert_nil company.reload.logo_url
  end

  test "skips unverified logo candidates" do
    company = companies(:one)
    company.update!(logo_url: nil)

    result = LogoFetcherService.backfill_missing_logos(scope: Company.where(id: company.id), dry_run: false, limit: nil, provider: :duckduckgo, verifier: ->(_url) { false }, logger: nil)

    assert_equal 1, result.skipped_unverified
    assert_nil company.reload.logo_url
  end

  test "prefers configured logo dev publishable candidate" do
    company = companies(:one)
    company.update!(logo_url: nil)

    original_token = ENV["LOGO_DEV_PUBLISHABLE_KEY"]
    ENV["LOGO_DEV_PUBLISHABLE_KEY"] = "pk_test"
    begin
      result = LogoFetcherService.backfill_missing_logos(scope: Company.where(id: company.id), dry_run: true, limit: nil, verifier: ->(_url) { true }, logger: nil)

      assert_equal "https://img.logo.dev/example.com?token=pk_test&size=128&format=png&fallback=404", result.examples.first[:logo_url]
    ensure
      ENV["LOGO_DEV_PUBLISHABLE_KEY"] = original_token
    end
  end
end
