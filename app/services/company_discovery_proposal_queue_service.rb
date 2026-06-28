class CompanyDiscoveryProposalQueueService
  SOURCE = CompanyDiscoveryService::SOURCE
  PROPOSAL_TYPE = CompanyDiscoveryService::PROPOSAL_TYPE

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(pipeline_run:, candidate_indexes:, admin_user:)
    @pipeline_run = pipeline_run
    @candidate_indexes = Array(candidate_indexes).map(&:to_i)
    @admin_user = admin_user
  end

  def call
    validate_run!
    raise ArgumentError, "Select at least one candidate" if candidate_indexes.empty?

    candidate_indexes.filter_map do |index|
      candidate = Array(pipeline_run.details&.fetch("candidates", []))[index]
      next unless candidate.present? && candidate["status"] == "absent_candidate"

      CompanyCandidateRowProcessorService.call(
        candidate: candidate.merge("pipeline_run_id" => pipeline_run.id),
        index: index,
        admin_user: admin_user,
        pipeline_run_id: pipeline_run.id,
        source: SOURCE,
        proposal_type: PROPOSAL_TYPE,
        source_label: "LLM Discovery",
        skip_auto_draft: true
      )
    end
  end

  private

  attr_reader :pipeline_run, :candidate_indexes, :admin_user

  def validate_run!
    raise ArgumentError, "Pipeline run is not a company discovery run" unless pipeline_run.run_type == CompanyDiscoveryService::RUN_TYPE
  end
end
