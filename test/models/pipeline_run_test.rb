require "test_helper"

class PipelineRunTest < ActiveSupport::TestCase
  test "requires valid status" do
    run = PipelineRun.new(name: "Verifier", run_type: "company_verification", status: "unknown")

    assert_not run.valid?
    assert_includes run.errors[:status], "is not included in the list"
  end

  test "mark_running records running status and start time" do
    run = PipelineRun.create!(name: "Verifier", run_type: "company_verification")

    run.mark_running!

    assert_equal "running", run.status
    assert_not_nil run.started_at
  end

  test "mark_succeeded records completion details" do
    run = PipelineRun.create!(name: "Verifier", run_type: "company_verification")

    run.mark_succeeded!(records_processed: 3, details: { "verdict" => "needs_review" })

    assert_equal "succeeded", run.status
    assert_equal 3, run.records_processed
    assert_equal "needs_review", run.details["verdict"]
    assert_not_nil run.finished_at
  end

  test "mark_failed records error message" do
    run = PipelineRun.create!(name: "Verifier", run_type: "company_verification")

    run.mark_failed!("provider timeout")

    assert_equal "failed", run.status
    assert_equal "provider timeout", run.error_message
    assert_not_nil run.finished_at
  end

  test "for_company scope finds runs linked in details json" do
    company = companies(:one)
    linked = PipelineRun.create!(name: "Agent company review: #{company.name}", run_type: "company_agent_review", status: "succeeded", details: { "company_id" => company.id })
    PipelineRun.create!(name: "Other company review", run_type: "company_agent_review", status: "succeeded", details: { "company_id" => companies(:two).id })

    assert_includes PipelineRun.for_company(company), linked
    assert_equal 1, PipelineRun.for_company(company).count
  end
end
