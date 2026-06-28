class UserContributionProcessingJob < ApplicationJob
  queue_as :default

  def perform(proposal_id)
    proposal = CompanyProposal.find_by(id: proposal_id)
    return unless proposal

    CompanyUserSubmissionProcessorService.call(proposal: proposal)
  end
end
