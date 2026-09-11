require "test_helper"

class CompanyReviewMarkServiceTest < ActiveSupport::TestCase
  test "mark verified sets quality fields and timestamps" do
    company = companies(:one)
    company.update_columns(quality_status: nil, verification_verdict: nil, human_reviewed_at: nil, verified_at: nil)

    CompanyReviewMarkService.call(company: company, decision: "verified")
    company.reload

    assert_equal "verified", company.quality_status
    assert_equal "human_confirmed", company.verification_verdict
    assert company.human_reviewed_at.present?
    assert company.quality_reviewed_at.present?
    assert company.verified_at.present?
  end

  test "mark needs work keeps company visible" do
    company = companies(:one)
    company.update_columns(quality_status: nil, visible: true)

    CompanyReviewMarkService.call(company: company, decision: "needs_work")
    company.reload

    assert_equal "needs_review", company.quality_status
    assert_equal "needs_human_review", company.verification_verdict
    assert company.visible?
  end

  test "mark reject hides company" do
    company = companies(:one)
    company.update_columns(quality_status: nil, visible: true)

    CompanyReviewMarkService.call(company: company, decision: "reject")
    company.reload

    assert_equal "rejected", company.quality_status
    assert_equal "human_rejected", company.verification_verdict
    assert_not company.visible?
  end

  test "raises for unknown decision" do
    assert_raises(ArgumentError) do
      CompanyReviewMarkService.call(company: companies(:one), decision: "unknown")
    end
  end

  # ---- the write is confirmed, not assumed ---------------------------------

  # An in-memory record reports whatever was assigned to it, which is not evidence that
  # the database accepted it. A reviewer told their decision landed will not make it a
  # second time, so a write that did not save has to surface as a failure.
  test "a write that reports success but saves nothing is reported as a failure" do
    company = companies(:one)
    company.update_columns(quality_status: nil, verification_verdict: nil)

    error = assert_raises(CompanyReviewMarkService::NotConfirmed) do
      company.stub(:update!, true) do
        CompanyReviewMarkService.call(company: company, decision: "verified", admin_user: admin_users(:one))
      end
    end

    assert_match(/reported success, but the value was not saved/, error.message)
    assert_includes error.unconfirmed.keys, "quality_status"
    assert_equal "verified", error.unconfirmed["quality_status"]["requested"]
    assert_nil error.unconfirmed["quality_status"]["saved"]
  end

  test "a confirmed write raises nothing and returns the company" do
    company = companies(:one)
    company.update_columns(quality_status: nil)

    assert_equal company, CompanyReviewMarkService.call(company: company, decision: "verified")
  end

  # ---- what the reviewer did is recorded -----------------------------------

  test "a reviewer decision is recorded with who, what and the status either side" do
    company = companies(:one)
    company.update_columns(quality_status: "needs_review", verification_verdict: nil)

    assert_difference -> { PipelineRun.where(run_type: ReviewerActionAudit::RUN_TYPE).count }, 1 do
      CompanyReviewMarkService.call(company: company, decision: "verified", admin_user: admin_users(:one),
                                    context: { queue: { review_state: "not_reviewed" } })
    end

    run = PipelineRun.where(run_type: ReviewerActionAudit::RUN_TYPE).order(:created_at).last
    assert_equal "succeeded", run.status
    assert_equal admin_users(:one).email, run.agent_name
    assert_equal company.id, run.details["company_id"]
    assert_equal "verified", run.details["action_type"]
    assert_equal "needs_review", run.details["previous_status"]
    assert_equal "verified", run.details["final_status"]
    assert_equal({ "review_state" => "not_reviewed" }, run.details["originating_queue"])
    assert_includes PipelineRun.for_company(company), run, "the record's own activity list has to show it"
  end

  test "an action that saved nothing is recorded as a failure rather than left out" do
    company = companies(:one)
    company.update_columns(quality_status: nil)

    assert_difference -> { PipelineRun.where(run_type: ReviewerActionAudit::RUN_TYPE).count }, 1 do
      assert_raises(CompanyReviewMarkService::NotConfirmed) do
        company.stub(:update!, true) { CompanyReviewMarkService.call(company: company, decision: "verified") }
      end
    end

    run = PipelineRun.where(run_type: ReviewerActionAudit::RUN_TYPE).order(:created_at).last
    assert_equal "failed", run.status
    assert run.details["unconfirmed_values"].present?
  end

  test "a refused action is recorded with the reason" do
    company = companies(:one)
    company.update_columns(quality_status: nil)

    assert_difference -> { PipelineRun.where(run_type: ReviewerActionAudit::RUN_TYPE).count }, 1 do
      assert_raises(ArgumentError) do
        CompanyReviewMarkService.call(company: company, decision: "return_to_contributor", instructions: " ")
      end
    end

    run = PipelineRun.where(run_type: ReviewerActionAudit::RUN_TYPE).order(:created_at).last
    assert_equal "failed", run.status
    assert_match(/what the contributor needs/, run.details["error_details"])
  end

  test "returning a record to its contributor records the message and the fields" do
    company = companies(:one)
    company.update_columns(quality_status: nil, visible: true)

    CompanyReviewMarkService.call(company: company, decision: "return_to_contributor", admin_user: admin_users(:one),
                                  instructions: "The website returns a 404 — please provide a current URL.",
                                  fields: %w[main_url founded_date])

    run = PipelineRun.where(run_type: ReviewerActionAudit::RUN_TYPE).order(:created_at).last
    assert_equal "return_to_contributor", run.details["action_type"]
    assert_match(/404/, run.details["contributor_message"])
    assert_equal %w[main_url founded_date], run.details["fields_returned_to_contributor"]
    assert_equal "awaiting_contributor", run.details["final_status"]
  end

  # An audit row is a record of the decision, not a precondition for it.
  test "an audit that cannot be written does not take the decision down with it" do
    company = companies(:one)
    company.update_columns(quality_status: nil)

    PipelineRun.stub(:create!, ->(*) { raise ActiveRecord::StatementInvalid, "audit table unavailable" }) do
      CompanyReviewMarkService.call(company: company, decision: "verified")
    end

    assert_equal "verified", company.reload.quality_status
  end
end
