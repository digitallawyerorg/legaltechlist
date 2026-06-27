require "test_helper"

class CompanyDuplicateConsolidationServiceTest < ActiveSupport::TestCase
  test "keeps stronger same-domain company and deletes duplicate after transferring references" do
    keeper = companies(:one)
    duplicate = companies(:two)
    proposal = CompanyProposal.create!(
      status: "approved_to_draft",
      proposal_type: "atlas_candidate",
      source: "legaltechatlas_csv",
      source_identifier: "tryandai.com",
      company: duplicate
    )
    import_run = CompanyImportRun.create!(filename: "test.csv", total_rows: 1)
    import_row = CompanyImportRow.create!(company_import_run: import_run, row_number: 1, company: duplicate)
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
    assert_nil Company.find_by(id: duplicate.id)
    assert_equal "source_verified", keeper.quality_status
    assert_equal "https://www.crunchbase.com/organization/and-ai", keeper.source_url
    assert_equal "duplicate_consolidation_keeper", keeper.verification_verdict
    assert_equal [tags(:one).id, tags(:two).id].sort, keeper.tags.reload.pluck(:id).sort
    assert_equal keeper, proposal.reload.company
    assert_equal keeper, import_row.reload.company
    assert_equal [duplicate.id], run.details["results"].first["deleted_company_ids"]
    assert_equal({ "taggings" => 1, "company_proposals" => 1, "company_import_rows" => 1, "active_storage_attachments" => 0 }, run.details["results"].first["transferred_associations"][duplicate.id.to_s])
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

  test "deletes hidden duplicate remnant when visible keeper exists" do
    keeper = companies(:one)
    duplicate = companies(:two)
    keeper.update_columns(main_url: "https://www.moonlit.ai", canonical_domain: "moonlit.ai", visible: true)
    duplicate.update_columns(main_url: "https://moonlit.ai", canonical_domain: "moonlit.ai", visible: false, quality_status: "duplicate_hidden", verification_verdict: "duplicate_consolidated_into_#{keeper.id}")

    run = CompanyDuplicateConsolidationService.call(domains: ["moonlit.ai"], reviewer: "test@example.com")

    assert_equal "succeeded", run.status
    assert keeper.reload.visible?
    assert_nil Company.find_by(id: duplicate.id)
    assert_equal [duplicate.id], run.details["results"].first["deleted_company_ids"]
  end
end
