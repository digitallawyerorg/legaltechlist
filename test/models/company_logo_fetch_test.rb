require "test_helper"

class CompanyLogoFetchTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @original_twitter_publish = Rails.application.config.respond_to?(:twitter_publish) ? Rails.application.config.twitter_publish : nil
    Rails.application.config.twitter_publish = false
  end

  teardown do
    Rails.application.config.twitter_publish = @original_twitter_publish
  end

  test "publishing a company fetches missing logo" do
    company = build_company(visible: true)

    with_logo_dev_key("pk_test") do
      with_stubbed_logo_network do
        company.save!
        perform_enqueued_jobs

        assert company.reload.company_logo.present?
      end
    end
  end

  test "making a hidden company visible fetches missing logo" do
    company = build_company(visible: false)
    company.save!

    with_logo_dev_key("pk_test") do
      with_stubbed_logo_network do
        company.update!(visible: true)
        perform_enqueued_jobs

        assert company.reload.company_logo.present?
      end
    end
  end

  test "does not fetch logo when stored logo already exists" do
    company = build_company(visible: true)
    company.save!
    CompanyLogo.create!(company: company, data: stub_png_bytes, content_type: "image/png")

    with_logo_dev_key("pk_test") do
      with_stubbed_logo_network do
        company.update!(description: "#{company.description} updated")

        assert_equal stub_png_bytes, company.reload.company_logo.data
      end
    end
  end

  test "does not fetch logo when legacy external logo url is set" do
    company = build_company(visible: true, logo_url: "https://cdn.example.com/logo.png")

    with_logo_dev_key("pk_test") do
      with_stubbed_logo_network do
        company.save!

        assert_nil company.reload.company_logo
      end
    end
  end

  test "does not fetch logo without a canonical domain" do
    company = build_company(visible: true, main_url: "Unknown")

    with_logo_dev_key("pk_test") do
      with_stubbed_logo_network do
        company.save!

        assert_nil company.reload.company_logo
      end
    end
  end

  test "import worker publish fetches logo when update_columns skips callbacks" do
    company = build_company(visible: false)
    company.save!
    proposal = CompanyProposal.create!(
      status: "approved_to_draft",
      proposal_type: "atlas_candidate",
      source: "legaltechatlas_csv",
      source_identifier: "logo-worker-test-#{SecureRandom.hex(4)}",
      company: company,
      proposed_changes: { "name" => company.name, "main_url" => company.main_url },
      final_changes: { "name" => company.name, "main_url" => company.main_url }
    )
    result = { "action" => "auto_drafted", "proposal_id" => proposal.id, "company_id" => company.id }
    quality = { "publish_ready" => true, "warnings" => [] }

    with_logo_dev_key("pk_test") do
      with_stubbed_logo_network do
        out = CompanyImportWorkerService.new.send(:publish_if_ready, result, quality)
        assert_equal "published", out["action"]

        company.reload
        assert company.visible?
        assert company.company_logo.present?
      end
    end
  end

  test "missing logo dev key does not raise during automatic fetch" do
    company = build_company(visible: true)

    with_logo_dev_key(nil) do
      assert_nothing_raised do
        company.save!
        perform_enqueued_jobs
      end

      assert_nil company.reload.company_logo
    end
  end

  private

  def build_company(visible:, main_url: "https://www.example.com", logo_url: nil)
    companies(:one).dup.tap do |company|
      company.name = "Logo Fetch #{SecureRandom.hex(4)}"
      company.main_url = main_url
      company.logo_url = logo_url
      company.visible = visible
      company.skip_geocoding = true
    end
  end

  def stub_png_bytes
    "\x89PNG\r\n\x1a\n".b
  end

  def with_stubbed_logo_network
    png = stub_png_bytes
    original = LogoFetcherService.method(:fetch_for_company)
    LogoFetcherService.define_singleton_method(:fetch_for_company) do |company, **_kwargs|
      LogoFetcherService.backfill_missing_logos(
        scope: Company.where(id: company.id),
        dry_run: false,
        limit: 1,
        logger: nil,
        verifier: ->(_url) { true },
        downloader: ->(_url) { { data: png, content_type: "image/png" } }
      )
    end
    yield
  ensure
    LogoFetcherService.define_singleton_method(:fetch_for_company, original)
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
