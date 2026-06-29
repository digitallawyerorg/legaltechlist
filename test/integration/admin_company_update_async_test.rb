require "test_helper"

class AdminCompanyUpdateAsyncTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  setup do
    @original_twitter_publish = Rails.application.config.respond_to?(:twitter_publish) ? Rails.application.config.twitter_publish : nil
    Rails.application.config.twitter_publish = false
  end

  teardown do
    Rails.application.config.twitter_publish = @original_twitter_publish
  end

  test "admin company update enqueues atlas sync and logo fetch instead of running them synchronously" do
    sign_in admin_users(:one)
    company = companies(:one)
    company.update_columns(visible: false, legaltech_atlas_url: nil, logo_url: nil)
    company.company_logo&.destroy

    sync_called = false
    logo_fetch_called = false
    original_sync = LegaltechAtlasLinkSyncService.method(:sync_one)
    original_fetch = LogoFetcherService.method(:fetch_for_company)

    LegaltechAtlasLinkSyncService.define_singleton_method(:sync_one) do |*args, **kwargs|
      sync_called = true
      original_sync.call(*args, **kwargs)
    end
    LogoFetcherService.define_singleton_method(:fetch_for_company) do |*args, **kwargs|
      logo_fetch_called = true
      original_fetch.call(*args, **kwargs)
    end

    assert_enqueued_with(job: LegaltechAtlasLinkSyncJob, args: [company.id]) do
      assert_enqueued_with(job: CompanyLogoFetchJob, args: [company.id]) do
        patch custom_admin_company_path(company), params: {
          company: {
            name: company.name,
            description: company.description,
            main_url: company.main_url,
            location: company.location,
            founded_date: company.founded_date,
            category_id: company.category_id,
            business_model_id: company.business_model_id,
            target_client_id: company.target_client_id,
            legalio_url: "https://www.legal.io/legal-software/130/test",
            visible: true
          }
        }
      end
    end

    assert_redirected_to custom_admin_company_review_path(company)
    assert_not sync_called, "expected LegaltechAtlasLinkSyncService.sync_one not to run during the HTTP request"
    assert_not logo_fetch_called, "expected LogoFetcherService.fetch_for_company not to run during the HTTP request"
  ensure
    LegaltechAtlasLinkSyncService.define_singleton_method(:sync_one, original_sync)
    LogoFetcherService.define_singleton_method(:fetch_for_company, original_fetch)
  end

  test "admin company update with legalio url only does not enqueue slow follow-up jobs" do
    sign_in admin_users(:one)
    company = companies(:one)

    assert_no_enqueued_jobs only: [LegaltechAtlasLinkSyncJob, CompanyLogoFetchJob] do
      patch custom_admin_company_path(company), params: {
        company: {
          name: company.name,
          description: company.description,
          main_url: company.main_url,
          location: company.location,
          founded_date: company.founded_date,
          category_id: company.category_id,
          business_model_id: company.business_model_id,
          target_client_id: company.target_client_id,
          legalio_url: "https://www.legal.io/legal-software/130/test",
          visible: company.visible
        }
      }
    end

    assert_redirected_to custom_admin_company_review_path(company)
    assert_equal "https://www.legal.io/legal-software/130/test", company.reload.legalio_url
  end
end
