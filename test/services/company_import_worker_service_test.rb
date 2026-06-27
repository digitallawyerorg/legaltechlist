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
      assert_equal 1, CompanyImportWorkerService.drain(run_id: run.id, batch_limit: 1)
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

  test "worker recovers stale processing rows" do
    run = nil
    with_import_csv do |path|
      run = CompanyImportSeedService.call(file: path, filename: "worker-test.csv", reviewer: "test@example.com", limit: 1)
    end
    row = run.company_import_rows.first
    row.update!(status: "processing", locked_at: 30.minutes.ago)

    assert_equal 1, CompanyImportWorkerService.drain(run_id: run.id, batch_limit: 1)

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
end
