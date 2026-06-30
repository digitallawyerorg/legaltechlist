class CompanyDiscoveryJob < ApplicationJob
  queue_as :default

  def perform(run_id, arguments = {})
    CompanyDiscoveryService.perform_run!(run_id, arguments)
  rescue ArgumentError, CompanyDiscoveryService::CostLimitExceededError => e
    run = PipelineRun.find_by(id: run_id)
    run&.mark_failed!(e.message)
  end
end
