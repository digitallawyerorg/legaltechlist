require "test_helper"

class LogoFetcherServiceTest < ActiveSupport::TestCase
  test "dry run reports verified logo dev logos without updating records" do
    company = companies(:one)
    company.update!(logo_url: nil)

    with_logo_dev_key("pk_test") do
      result = LogoFetcherService.backfill_missing_logos(scope: Company.where(id: company.id), dry_run: true, limit: nil, verifier: ->(_url) { true }, downloader: stub_downloader, logger: nil)

      assert_equal 1, result.checked
      assert_equal 1, result.updated
      assert_nil company.reload.logo_url
      assert_nil company.company_logo
      assert_equal "example.com", result.examples.first[:domain]
      assert_equal "image/png", result.examples.first[:content_type]
    end
  end

  test "updates missing logos when not a dry run" do
    company = companies(:one)
    company.update!(logo_url: nil)

    with_logo_dev_key("pk_test") do
      result = LogoFetcherService.backfill_missing_logos(scope: Company.where(id: company.id), dry_run: false, limit: nil, verifier: ->(_url) { true }, downloader: stub_downloader, logger: nil)

      assert_equal 1, result.updated
      company.reload
      assert_nil company.logo_url
      assert_equal "image/png", company.company_logo.content_type
      assert_equal stub_png_bytes, company.company_logo.data
    end
  end

  test "replaces legacy external logo urls when no blob is stored" do
    company = companies(:one)
    company.update!(logo_url: "https://cdn.example.com/logo.png")

    with_logo_dev_key("pk_test") do
      result = LogoFetcherService.backfill_missing_logos(scope: Company.where(id: company.id), dry_run: false, limit: nil, verifier: ->(_url) { true }, downloader: stub_downloader, logger: nil)

      assert_equal 1, result.updated
      company.reload
      assert_nil company.logo_url
      assert_equal "image/png", company.company_logo.content_type
    end
  end

  test "replaces placeholder logos" do
    company = companies(:one)
    company.update!(logo_url: "https://placehold.co/64x64?text=T")

    with_logo_dev_key("pk_test") do
      result = LogoFetcherService.backfill_missing_logos(scope: Company.where(id: company.id), dry_run: false, limit: nil, verifier: ->(_url) { true }, downloader: stub_downloader, logger: nil)

      assert_equal 1, result.updated
      company.reload
      assert_nil company.logo_url
      assert company.company_logo.present?
    end
  end

  test "replaces duckduckgo favicon logos" do
    company = companies(:one)
    company.update!(logo_url: "https://icons.duckduckgo.com/ip3/example.com.ico")

    with_logo_dev_key("pk_test") do
      result = LogoFetcherService.backfill_missing_logos(scope: Company.where(id: company.id), dry_run: false, limit: nil, verifier: ->(_url) { true }, downloader: stub_downloader, logger: nil)

      assert_equal 1, result.updated
      company.reload
      assert_nil company.logo_url
      assert company.company_logo.present?
    end
  end

  test "replaces legacy logo dev urls" do
    company = companies(:one)
    company.update!(logo_url: "https://img.logo.dev/example.com?token=pk_test&size=128&format=png&fallback=404")

    with_logo_dev_key("pk_test") do
      result = LogoFetcherService.backfill_missing_logos(scope: Company.where(id: company.id), dry_run: false, limit: nil, verifier: ->(_url) { true }, downloader: stub_downloader, logger: nil)

      assert_equal 1, result.updated
      company.reload
      assert_nil company.logo_url
      assert company.company_logo.present?
    end
  end

  test "skips companies that already have stored logos" do
    company = companies(:one)
    company.update!(logo_url: nil)
    CompanyLogo.create!(company: company, data: stub_png_bytes, content_type: "image/png")

    with_logo_dev_key("pk_test") do
      result = LogoFetcherService.backfill_missing_logos(scope: Company.where(id: company.id), dry_run: false, limit: nil, verifier: ->(_url) { true }, downloader: stub_downloader, logger: nil)

      assert_equal 0, result.checked
      assert_equal 0, result.updated
    end
  end

  test "skips missing logos without a canonical domain" do
    company = companies(:one)
    company.update!(logo_url: nil, main_url: "Unknown")

    with_logo_dev_key("pk_test") do
      result = LogoFetcherService.backfill_missing_logos(scope: Company.where(id: company.id), dry_run: false, limit: nil, verifier: ->(_url) { true }, downloader: stub_downloader, logger: nil)

      assert_equal 1, result.skipped_no_domain
      assert_nil company.reload.logo_url
      assert_nil company.company_logo
    end
  end

  test "skips unverified logo candidates" do
    company = companies(:one)
    company.update!(logo_url: nil)

    with_logo_dev_key("pk_test") do
      result = LogoFetcherService.backfill_missing_logos(scope: Company.where(id: company.id), dry_run: false, limit: nil, verifier: ->(_url) { false }, downloader: stub_downloader, logger: nil)

      assert_equal 1, result.skipped_unverified
      assert_nil company.reload.logo_url
      assert_nil company.company_logo
    end
  end

  test "skips when download fails" do
    company = companies(:one)
    company.update!(logo_url: nil)

    with_logo_dev_key("pk_test") do
      result = LogoFetcherService.backfill_missing_logos(scope: Company.where(id: company.id), dry_run: false, limit: nil, verifier: ->(_url) { true }, downloader: ->(_url) { nil }, logger: nil)

      assert_equal 1, result.skipped_unverified
      assert_nil company.reload.company_logo
    end
  end

  test "requires configured logo dev api key" do
    company = companies(:one)
    company.update!(logo_url: nil)

    with_logo_dev_key(nil) do
      error = assert_raises LogoFetcherService::MissingConfiguration do
        LogoFetcherService.backfill_missing_logos(scope: Company.where(id: company.id), dry_run: true, limit: nil, verifier: ->(_url) { true }, downloader: stub_downloader, logger: nil)
      end

      assert_match "LOGO_DEV_API_KEY", error.message
    end
  end

  test "rejects logo dev secret keys for stored image URLs" do
    company = companies(:one)
    company.update!(logo_url: nil)

    with_logo_dev_key("sk_test") do
      error = assert_raises LogoFetcherService::MissingConfiguration do
        LogoFetcherService.backfill_missing_logos(scope: Company.where(id: company.id), dry_run: true, limit: nil, verifier: ->(_url) { true }, downloader: stub_downloader, logger: nil)
      end

      assert_match "publishable", error.message
    end
  end

  test "fetch_for_company stores a logo for one company" do
    company = companies(:one)
    company.update!(logo_url: nil)

    with_logo_dev_key("pk_test") do
      result = LogoFetcherService.fetch_for_company(company, verifier: ->(_url) { true }, downloader: stub_downloader)

      assert_equal 1, result.updated
      assert_equal "image/png", company.reload.company_logo.content_type
    end
  end

  test "fetch_for_company skips when logo dev is not configured" do
    company = companies(:one)
    company.update!(logo_url: nil)

    with_logo_dev_key(nil) do
      assert_nil LogoFetcherService.fetch_for_company(company, verifier: ->(_url) { true }, downloader: stub_downloader)
      assert_nil company.reload.company_logo
    end
  end

  test "verifier falls back to get when head is not successful" do
    service = LogoFetcherService.new(scope: Company.none, dry_run: true, limit: nil, provider: :logo_dev, logger: nil, verifier: nil, downloader: nil)
    head_response = Net::HTTPNotFound.new("1.1", "404", "Not Found")
    get_response = Net::HTTPOK.new("1.1", "200", "OK")
    get_response["content-type"] = "image/png"
    service.define_singleton_method(:requests) { @requests ||= [head_response, get_response] }
    service.define_singleton_method(:request) { |_uri, _request_class| requests.shift }

    assert service.send(:verified_image_url?, "https://img.logo.dev/example.com")
  end

  test "downloader stores binary image data" do
    service = LogoFetcherService.new(scope: Company.none, dry_run: true, limit: nil, provider: :logo_dev, logger: nil, verifier: nil, downloader: nil)
    response = fake_http_response(stub_png_bytes, "image/png; charset=binary")
    service.define_singleton_method(:request) { |_uri, _request_class| response }

    image = service.send(:download_image, "https://img.logo.dev/example.com")

    assert_equal "image/png", image[:content_type]
    assert_equal stub_png_bytes, image[:data]
  end

  private

  def stub_png_bytes
    "\x89PNG\r\n\x1a\n".b
  end

  def stub_downloader
    ->(_url) { { data: stub_png_bytes, content_type: "image/png" } }
  end

  def fake_http_response(body, content_type)
    response = Struct.new(:body).new(body)
    response.define_singleton_method(:is_a?) { |klass| klass == Net::HTTPSuccess }
    response.define_singleton_method(:[]) { |key| key == "content-type" ? content_type : nil }
    response
  end

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
