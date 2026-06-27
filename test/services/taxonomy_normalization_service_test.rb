require "test_helper"

class TaxonomyNormalizationServiceTest < ActiveSupport::TestCase
  test "maps compound target client strings to canonical values" do
    names = TaxonomyNormalizationService.canonical_target_client_names("Companies, Corporate Legal, Government")

    assert_equal ["Corporate Legal", "Government"], names
  end

  test "maps legacy revenue model names to canonical values" do
    names = TaxonomyNormalizationService.canonical_revenue_model_names("SaaS")

    assert_equal ["Subscription"], names
  end
end
