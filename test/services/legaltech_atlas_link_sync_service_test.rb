require "test_helper"

class LegaltechAtlasLinkSyncServiceTest < ActiveSupport::TestCase
  test "syncs atlas urls from csv by domain and name" do
    file_path = Rails.root.join("test/fixtures/legaltech_atlas_links.csv")

    result = LegaltechAtlasLinkSyncService.call(
      source: :csv,
      file: file_path,
      dry_run: false,
      scope: Company.all
    )

    assert_equal 1, result.matched
    assert_equal 1, result.updated
    assert_equal 1, result.unmatched_csv_rows

    company = companies(:one).reload
    assert_equal "https://legaltechatlas.com/companies/test-company-one", company.legaltech_atlas_url
  end

  test "syncs atlas urls from sitemap by slugified company name" do
    result = LegaltechAtlasLinkSyncService.call(
      source: :sitemap,
      dry_run: false,
      scope: Company.where(id: companies(:one).id),
      sitemap_index: {
        "test-company-one" => "https://legaltechatlas.com/companies/test-company-one"
      }
    )

    assert_equal 1, result.matched
    assert_equal 1, result.updated
    assert_equal "https://legaltechatlas.com/companies/test-company-one", companies(:one).reload.legaltech_atlas_url
  end

  test "dry run does not persist atlas urls" do
    file_path = Rails.root.join("test/fixtures/legaltech_atlas_links.csv")

    LegaltechAtlasLinkSyncService.call(
      source: :csv,
      file: file_path,
      dry_run: true,
      scope: Company.where(id: companies(:one).id)
    )

    assert_nil companies(:one).reload.legaltech_atlas_url
  end
end
