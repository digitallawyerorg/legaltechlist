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
    called_with = nil
    original = CompanyDiscoveryService.method(:perform_run!)
    CompanyDiscoveryService.define_singleton_method(:perform_run!) do |run_id, args|
      called_with = [run_id, args]
    end

    CompanyDiscoveryJob.perform_now(run.id, arguments)

    assert_equal [run.id, arguments], called_with
  ensure
    CompanyDiscoveryService.define_singleton_method(:perform_run!, original)
  end
end
