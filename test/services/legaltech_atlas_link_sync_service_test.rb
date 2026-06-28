require "test_helper"

class LegaltechAtlasLinkSyncServiceTest < ActiveSupport::TestCase
  API_INDEX = [
    {
      "slug" => "test-company-one",
      "name" => "Test Company One",
      "canonical_domain" => "example.com",
      "atlas_url" => "https://legaltechatlas.com/companies/test-company-one"
    },
    {
      "slug" => "domain-match-co",
      "name" => "Domain Match Co",
      "canonical_domain" => "domain-match.example",
      "atlas_url" => "https://legaltechatlas.com/companies/domain-match-co"
    },
    {
      "slug" => "slug-only-co",
      "name" => "Slug Only Co",
      "canonical_domain" => "slug-only.example",
      "atlas_url" => "https://legaltechatlas.com/companies/slug-only-co"
    }
  ].freeze

  test "syncs atlas urls from api by domain name and slug priority" do
    companies(:one).update_columns(main_url: "https://www.example.com", canonical_domain: "example.com")
    domain_company = Company.create!(
      name: "Other Name",
      location: "Boston, MA",
      country: "United States",
      city: "Boston",
      founded_date: 2020,
      description: "Another test company description that is long enough",
      main_url: "https://domain-match.example",
      canonical_domain: "domain-match.example",
      visible: true,
      category_id: categories(:one).id,
      business_model_id: business_models(:one).id,
      target_client_id: target_clients(:one).id,
      sub_category_id: sub_categories(:one).id
    )
    slug_company = Company.create!(
      name: "Slug Only Co",
      location: "Austin, TX",
      country: "United States",
      city: "Austin",
      founded_date: 2020,
      description: "Another test company description that is long enough",
      main_url: "https://unrelated.example",
      visible: true,
      category_id: categories(:one).id,
      business_model_id: business_models(:one).id,
      target_client_id: target_clients(:one).id,
      sub_category_id: sub_categories(:one).id
    )

    result = LegaltechAtlasLinkSyncService.call(
      source: :api,
      dry_run: false,
      scope: Company.where(id: [companies(:one).id, domain_company.id, slug_company.id]),
      api_index: API_INDEX
    )

    assert_equal 3, result.matched
    assert_equal 3, result.updated
    assert_equal "https://legaltechatlas.com/companies/test-company-one", companies(:one).reload.legaltech_atlas_url
    assert_equal "https://legaltechatlas.com/companies/domain-match-co", domain_company.reload.legaltech_atlas_url
    assert_equal "https://legaltechatlas.com/companies/slug-only-co", slug_company.reload.legaltech_atlas_url
  end

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

  test "skips ambiguous api matches" do
    companies(:one).update_columns(main_url: "https://example.com", canonical_domain: "example.com")

    result = LegaltechAtlasLinkSyncService.call(
      source: :api,
      dry_run: false,
      scope: Company.where(id: companies(:one).id),
      api_index: [
        { "slug" => "one", "name" => "One", "canonical_domain" => "example.com", "atlas_url" => "https://legaltechatlas.com/companies/one" },
        { "slug" => "two", "name" => "Two", "canonical_domain" => "example.com", "atlas_url" => "https://legaltechatlas.com/companies/two" }
      ]
    )

    assert_equal 0, result.matched
    assert_nil companies(:one).reload.legaltech_atlas_url
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
