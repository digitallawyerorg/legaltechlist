require "test_helper"

class DiscoveryNonprofitAdvocacyFilterTest < ActiveSupport::TestCase
  test "rejects advocacy nonprofit with org domain" do
    candidate = {
      "name" => "JustFix",
      "website" => "https://justfix.org",
      "description" => "Tenant advocacy nonprofit helping renters fight evictions.",
      "why_discovered" => "Housing justice advocacy organization."
    }

    assert DiscoveryNonprofitAdvocacyFilter.rejected?(candidate)
    assert_equal "nonprofit_advocacy_keyword", DiscoveryNonprofitAdvocacyFilter.rejection_reason(candidate)
  end

  test "does not reject commercial legal tech vendor" do
    candidate = {
      "name" => "ContractFlow",
      "website" => "https://contractflow.com",
      "description" => "SaaS contract lifecycle management platform for law firms.",
      "why_discovered" => "Legal tech vendor in CLM category."
    }

    refute DiscoveryNonprofitAdvocacyFilter.rejected?(candidate)
  end

  test "does not reject org domain without nonprofit signals" do
    candidate = {
      "name" => "Open Legal Stack",
      "website" => "https://openlegalstack.org",
      "description" => "Open-source legal technology platform for enterprise legal teams.",
      "why_discovered" => "B2B legal software vendor."
    }

    refute DiscoveryNonprofitAdvocacyFilter.rejected?(candidate)
  end
end
