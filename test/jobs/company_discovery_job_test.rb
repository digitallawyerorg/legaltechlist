require "test_helper"

class CompanyDiscoveryJobTest < ActiveJob::TestCase
  test "enqueue creates pending run and enqueues background job" do
    assert_enqueued_with(job: CompanyDiscoveryJob) do
      run = CompanyDiscoveryService.enqueue(
        discovery_type: "country",
        country: "Canada",
        dry_run: true,
        admin_user: admin_users(:one),
        reviewer: admin_users(:one).email
      )

      assert_equal "pending", run.status
      assert_includes run.name, "Canada"
    end
  end

  test "perform delegates to CompanyDiscoveryService.perform_run!" do
    run = PipelineRun.create!(
      name: "Company discovery: Canada",
      run_type: CompanyDiscoveryService::RUN_TYPE,
      status: "pending",
      agent_name: CompanyDiscoveryService::AGENT_NAME
    )
    arguments = { "discovery_type" => "country", "country" => "Canada", "dry_run" => true }
    called = false

    CompanyDiscoveryService.stub(:perform_run!, lambda { |run_id, args|
      called = true
      assert_equal run.id, run_id
      assert_equal arguments, args
    }) do
      CompanyDiscoveryJob.perform_now(run.id, arguments)
    end

    assert called
  end
end
