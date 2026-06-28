require "test_helper"

class ReadOnlyEvidenceToolsTest < ActiveSupport::TestCase
  test "domain normalization tool returns canonical read-only identity fields" do
    result = DomainNormalizationTool.new.call({ name: "Example Co", url: "https://www.example.com/path" })

    assert_equal "example co", result["normalized_name"]
    assert_equal "example.com", result["canonical_domain"]
    assert result["fingerprint"].present?
    assert_equal true, result["read_only"]
  end

  test "duplicate lookup tool returns name and domain candidates without writes" do
    company = companies(:one)
    duplicate = companies(:two)
    duplicate.update_columns(name: company.name, main_url: "https://www.example.com")

    result = DuplicateLookupTool.new.call({ company_id: company.id, name: company.name, url: company.main_url })

    assert_equal true, result["read_only"]
    assert_includes result["name_candidates"].map { |candidate| candidate["id"] }, duplicate.id
    assert_includes result["domain_candidates"].map { |candidate| candidate["id"] }, duplicate.id
  end

  test "stored source lookup tool returns profile URLs for a company" do
    company = companies(:one)

    result = StoredSourceLookupTool.new.call({ company_id: company.id })

    assert_equal true, result["read_only"]
    assert_equal company.id, result["company_id"]
    assert_includes result["sources"].map { |source| source["label"] }, "main_url"
    assert_includes result["sources"].map { |source| source["domain"] }, "example.com"
  end

  test "taxonomy lookup tool returns current and available taxonomy values" do
    company = companies(:one)

    result = TaxonomyLookupTool.new.call({ company_id: company.id })

    assert_equal true, result["read_only"]
    assert_equal "Knowledge & Research", result["current"]["category"]
    assert_includes result["available"]["categories"], "Knowledge & Research"
    assert_includes result["available"]["revenue_models"], "Subscription"
    assert_includes result["available"]["target_clients"], "Law Firms"
  end

  test "web evidence tool defaults to no network checks" do
    company = companies(:one)

    result = WebEvidenceTool.new.call({ company_id: company.id })

    assert_equal true, result["read_only"]
    assert_equal false, result["network_checked"]
    assert_includes result["urls"].map { |source| source["status"] }, "not_checked"
    assert_includes result["urls"].map { |source| source["domain"] }, "example.com"
  end
end
