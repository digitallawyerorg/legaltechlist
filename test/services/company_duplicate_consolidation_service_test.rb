require "test_helper"

class CompanyDuplicateConsolidationServiceTest < ActiveSupport::TestCase
  test "keeps stronger same-domain company and hides duplicate" do
    keeper = companies(:one)
    duplicate = companies(:two)
    keeper.update_columns(
      name: "And AI",
      main_url: "https://www.tryandai.com/",
      canonical_domain: "tryandai.com",
      description: "And AI helps patent teams manage invention workflows, prior art research, and claim drafting.",
      source_url: nil
    )
    duplicate.update_columns(
      name: "AndAI",
      main_url: "https://tryandai.com",
      canonical_domain: "tryandai.com",
      description: "Tech enabled IP services",
      business_model_id: nil,
      source_url: "https://www.crunchbase.com/organization/and-ai"
    )

    run = CompanyDuplicateConsolidationService.call(domains: ["tryandai.com"], reviewer: "test@example.com")

    assert_equal "succeeded", run.status
    assert keeper.reload.visible?
    assert_not duplicate.reload.visible?
    assert_equal "source_verified", keeper.quality_status
    assert_equal "duplicate_hidden", duplicate.quality_status
    assert_equal "https://www.crunchbase.com/organization/and-ai", keeper.source_url
    assert_equal "duplicate_consolidation_keeper", keeper.verification_verdict
    assert_equal "duplicate_consolidated_into_#{keeper.id}", duplicate.verification_verdict
  end

  test "dry run records consolidation without changing companies" do
    keeper = companies(:one)
    duplicate = companies(:two)
    keeper.update_columns(main_url: "https://www.wordsmith.ai", canonical_domain: "wordsmith.ai")
    duplicate.update_columns(main_url: "https://wordsmith.ai", canonical_domain: "wordsmith.ai")

    run = CompanyDuplicateConsolidationService.call(domains: ["wordsmith.ai"], dry_run: true)

    assert_equal "succeeded", run.status
    assert keeper.reload.visible?
    assert duplicate.reload.visible?
    assert run.details["results"].first["dry_run"]
  end
end
