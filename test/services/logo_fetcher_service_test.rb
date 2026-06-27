require "test_helper"

class LogoFetcherServiceTest < ActiveSupport::TestCase
  test "dry run reports verified logo dev logos without updating records" do
    company = companies(:one)
    company.update!(logo_url: nil)

    with_logo_dev_key("pk_test") do
      result = LogoFetcherService.backfill_missing_logos(scope: Company.where(id: company.id), dry_run: true, limit: nil, verifier: ->(_url) { true }, logger: nil)

      assert_equal 1, result.checked
      assert_equal 1, result.updated
      assert_nil company.reload.logo_url
      assert_equal "example.com", result.examples.first[:domain]
      assert_equal "https://img.logo.dev/example.com?token=pk_test&size=128&format=png&fallback=404", result.examples.first[:logo_url]
    end
  end

  test "updates missing logos when not a dry run" do
    company = companies(:one)
    company.update!(logo_url: nil)

    with_logo_dev_key("pk_test") do
      result = LogoFetcherService.backfill_missing_logos(scope: Company.where(id: company.id), dry_run: false, limit: nil, verifier: ->(_url) { true }, logger: nil)

      assert_equal 1, result.updated
      assert_equal "https://img.logo.dev/example.com?token=pk_test&size=128&format=png&fallback=404", company.reload.logo_url
    end
  end

  test "skips companies with existing non-placeholder logos" do
    company = companies(:one)
    company.update!(logo_url: "https://cdn.example.com/logo.png")

    with_logo_dev_key("pk_test") do
      result = LogoFetcherService.backfill_missing_logos(scope: Company.where(id: company.id), dry_run: false, limit: nil, verifier: ->(_url) { true }, logger: nil)

      assert_equal 0, result.checked
      assert_equal 0, result.updated
      assert_equal "https://cdn.example.com/logo.png", company.reload.logo_url
    end
  end

  test "replaces placeholder logos" do
    company = companies(:one)
    company.update!(logo_url: "https://placehold.co/64x64?text=T")

    with_logo_dev_key("pk_test") do
      result = LogoFetcherService.backfill_missing_logos(scope: Company.where(id: company.id), dry_run: false, limit: nil, verifier: ->(_url) { true }, logger: nil)

      assert_equal 1, result.updated
      assert_equal "https://img.logo.dev/example.com?token=pk_test&size=128&format=png&fallback=404", company.reload.logo_url
    end
  end

  test "replaces duckduckgo favicon logos" do
    company = companies(:one)
    company.update!(logo_url: "https://icons.duckduckgo.com/ip3/example.com.ico")

    with_logo_dev_key("pk_test") do
      result = LogoFetcherService.backfill_missing_logos(scope: Company.where(id: company.id), dry_run: false, limit: nil, verifier: ->(_url) { true }, logger: nil)

      assert_equal 1, result.updated
      assert_equal "https://img.logo.dev/example.com?token=pk_test&size=128&format=png&fallback=404", company.reload.logo_url
    end
  end

  test "skips missing logos without a canonical domain" do
    company = companies(:one)
    company.update!(logo_url: nil, main_url: "Unknown")

    with_logo_dev_key("pk_test") do
      result = LogoFetcherService.backfill_missing_logos(scope: Company.where(id: company.id), dry_run: false, limit: nil, verifier: ->(_url) { true }, logger: nil)

      assert_equal 1, result.skipped_no_domain
      assert_nil company.reload.logo_url
    end
  end

  test "skips unverified logo candidates" do
    company = companies(:one)
    company.update!(logo_url: nil)

    with_logo_dev_key("pk_test") do
      result = LogoFetcherService.backfill_missing_logos(scope: Company.where(id: company.id), dry_run: false, limit: nil, verifier: ->(_url) { false }, logger: nil)

      assert_equal 1, result.skipped_unverified
      assert_nil company.reload.logo_url
    end
  end

  test "requires configured logo dev api key" do
    company = companies(:one)
    company.update!(logo_url: nil)

    with_logo_dev_key(nil) do
      error = assert_raises LogoFetcherService::MissingConfiguration do
        LogoFetcherService.backfill_missing_logos(scope: Company.where(id: company.id), dry_run: true, limit: nil, verifier: ->(_url) { true }, logger: nil)
      end

      assert_match "LOGO_DEV_API_KEY", error.message
    end
  end

  test "rejects logo dev secret keys for stored image URLs" do
    company = companies(:one)
    company.update!(logo_url: nil)

    with_logo_dev_key("sk_test") do
      error = assert_raises LogoFetcherService::MissingConfiguration do
        LogoFetcherService.backfill_missing_logos(scope: Company.where(id: company.id), dry_run: true, limit: nil, verifier: ->(_url) { true }, logger: nil)
      end

      assert_match "publishable", error.message
    end
  end

  private

  def with_logo_dev_key(value)
    original_api_key = ENV["LOGO_DEV_API_KEY"]
    original_publishable_key = ENV["LOGO_DEV_PUBLISHABLE_KEY"]
    ENV["LOGO_DEV_API_KEY"] = value
    ENV.delete("LOGO_DEV_PUBLISHABLE_KEY")
    yield
  ensure
    ENV["LOGO_DEV_API_KEY"] = original_api_key
    ENV["LOGO_DEV_PUBLISHABLE_KEY"] = original_publishable_key
  end
end
