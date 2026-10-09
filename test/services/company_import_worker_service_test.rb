require "test_helper"

class CompanyImportWorkerServiceTest < ActiveSupport::TestCase
  test "seeds csv rows into a resumable import run" do
    with_import_csv do |path|
      run = CompanyImportSeedService.call(file: path, filename: "worker-test.csv", reviewer: "test@example.com")

      assert_equal "pending", run.status
      assert_equal 2, run.total_rows
      assert_equal [1, 2], run.company_import_rows.order(:row_number).pluck(:row_number)
      assert_equal ["clean-worker.example", "example.com"], run.company_import_rows.order(:row_number).pluck(:source_identifier)
    end
  end

  test "worker processes rows one at a time and publishes only clean rows" do
    run = nil
    with_import_csv do |path|
      run = CompanyImportSeedService.call(file: path, filename: "worker-test.csv", reviewer: "test@example.com")
    end

    assert_difference "Company.count", 1 do
      with_site_evidence { assert_equal 1, CompanyImportWorkerService.drain(run_id: run.id, batch_limit: 1) }
    end

    first_row = run.company_import_rows.find_by!(row_number: 1)
    assert_equal "completed", first_row.status
    assert_equal "published", first_row.action
    assert first_row.company.visible?

    assert_no_difference "Company.count" do
      assert_equal 1, CompanyImportWorkerService.drain(run_id: run.id, batch_limit: 1)
    end

    duplicate_row = run.company_import_rows.find_by!(row_number: 2)
    assert_equal "completed", duplicate_row.status
    assert_equal "duplicate_merged", duplicate_row.action
    assert_equal companies(:one), duplicate_row.company
    assert_equal "succeeded", run.reload.status
  end

  test "worker resolves duplicate rows without enrichment" do
    run = nil
    with_import_csv do |path|
      run = CompanyImportSeedService.call(file: path, filename: "worker-test.csv", reviewer: "test@example.com", limit: 2)
    end
    run.company_import_rows.find_by!(row_number: 1).mark_skipped!(result: { "action" => "test_skip" })

    original_call = CompanyProposalEnrichmentService.method(:call)
    CompanyProposalEnrichmentService.define_singleton_method(:call) { |**| raise "duplicate row should not be enriched" }

    begin
      assert_no_difference "Company.count" do
        assert_equal 1, CompanyImportWorkerService.drain(run_id: run.id, batch_limit: 1)
      end
    ensure
      CompanyProposalEnrichmentService.define_singleton_method(:call, original_call)
    end

    duplicate_row = run.company_import_rows.find_by!(row_number: 2)
    assert_equal "completed", duplicate_row.status
    assert_equal "duplicate_merged", duplicate_row.action
    assert_equal companies(:one), duplicate_row.company
  end

  test "worker recovers stale processing rows" do
    run = nil
    with_import_csv do |path|
      run = CompanyImportSeedService.call(file: path, filename: "worker-test.csv", reviewer: "test@example.com", limit: 1)
    end
    row = run.company_import_rows.first
    row.update!(status: "processing", locked_at: 30.minutes.ago)

    with_site_evidence { assert_equal 1, CompanyImportWorkerService.drain(run_id: run.id, batch_limit: 1) }

    assert_equal "completed", row.reload.status
  end

  test "loop entrypoint calls drain without recursing" do
    worker = CompanyImportWorkerService.new(sleep_seconds: 1)
    calls = 0
    worker.define_singleton_method(:drain) do
      calls += 1
      raise "stop loop"
    end

    assert_raises(RuntimeError) { worker.loop }
    assert_equal 1, calls
  end

  private

  def with_import_csv
    Tempfile.create(["company_import_worker", ".csv"]) do |file|
      file.write(import_csv)
      file.close
      yield file.path
    end
  end

  def import_csv
    <<~CSV
      Organization Name,Organization Name URL,Industries,Founded Date,Headquarters Location,Description,Website,LinkedIn,Operating Status,Company Type,Total Funding Amount (in USD),Number of Funding Rounds,Number of Employees,Founders,Full Description
      Clean Worker Candidate,https://www.crunchbase.com/organization/clean-worker-candidate,"Legal Research, SaaS, Law Firms",2024-01-01,"Boston, Massachusetts, United States","Clean Worker Candidate builds legal research software for law firms.",https://clean-worker.example,https://www.linkedin.com/company/clean-worker,Active,For Profit,1000000,1,1-10,Jane Founder,"Clean Worker Candidate develops legal research software platforms for law firms and legal professionals."
      Test Company One,https://www.crunchbase.com/organization/test-company-one,"Legal Research, SaaS",2020-01-01,"San Francisco, California, United States","Duplicate of an existing company.",http://example.com,https://www.linkedin.com/company/test-company-one,Active,For Profit,1000000,1,1-10,Existing Founder,"Duplicate of an existing company."
    CSV
  end

  # The rule that closed the autopublish exposure: an unattended publish needs the
  # description verified, not merely complete.
  test "a row whose description was not verified is held rather than published" do
    run = nil
    with_import_csv do |path|
      run = CompanyImportSeedService.call(file: path, filename: "worker-test.csv", reviewer: "test@example.com", limit: 1)
    end

    assert_no_difference "Company.where(visible: true).count" do
      with_site_evidence(verified: false) { CompanyImportWorkerService.drain(run_id: run.id, batch_limit: 1) }
    end
    row = run.company_import_rows.first.reload
    assert_equal "held", row.status
    refute_equal "published", row.action
  end

  # How ~70 law firms came back: the scope pass hid them, then a re-import treated the
  # hidden row as an "already drafted" candidate and published it over that decision.
  test "a re-import never re-publishes a record that was hidden on purpose" do
    company = companies(:two)
    company.update_columns(visible: false, status: "active", quality_status: nil, verification_verdict: "out_of_scope_review")
    proposal = CompanyProposal.create!(status: "approved_to_draft", proposal_type: "atlas_candidate", source: "legaltechatlas_csv",
                                       source_identifier: "example2.com", company: company)
    quality = { "publish_ready" => true, "description_verified" => true, "warnings" => [] }

    result = CompanyImportWorkerService.allocate.send(:publish_if_ready, { "action" => "already_drafted", "proposal_id" => proposal.id }, quality)

    assert_equal "deliberately_hidden", result["publish_skipped"]
    company.reload
    assert_not company.visible?
    assert_equal "out_of_scope_review", company.verification_verdict
  end
end
