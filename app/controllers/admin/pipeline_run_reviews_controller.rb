module Admin
  class PipelineRunReviewsController < BaseController
    AGENT_REVIEW_RUN_TYPES = %w[company_agent_review duplicate_domain_review].freeze

    def index
      @activity = params[:activity].presence || "all"
      @status = params[:status].presence
      @pipeline_runs = pipeline_runs_scope.page(params[:page]).per(25)
      @activity_counts = {
        "all" => PipelineRun.count,
        "agent_reviews" => PipelineRun.where(run_type: AGENT_REVIEW_RUN_TYPES).count,
        "import_reviews" => PipelineRun.where(run_type: "atlas_candidate_import_review").count,
        "discovery_runs" => PipelineRun.where(run_type: CompanyDiscoveryService::RUN_TYPE).count,
        "failed" => PipelineRun.failed.count
      }
      @status_counts = {
        "all" => PipelineRun.count,
        "running" => PipelineRun.running.count,
        "failed" => PipelineRun.failed.count,
        "succeeded" => PipelineRun.where(status: "succeeded").count,
        "pending" => PipelineRun.where(status: "pending").count
      }
    end

    def show
      @pipeline_run = PipelineRun.find(params[:id])
      @details = @pipeline_run.details || {}
      @candidate_import_summary = @details["summary"] || {}
      @candidate_import_candidates = Array(@details["candidates"])
    end

    def queue_candidate_proposals
      pipeline_run = PipelineRun.find(params[:id])
      results = queue_proposals_for_run(pipeline_run)
      proposal_count = results.count { |result| result.is_a?(Hash) ? result["proposal_id"].present? : result&.id.present? }
      label = pipeline_run.run_type == CompanyDiscoveryService::RUN_TYPE ? "discovery candidate" : "candidate"

      redirect_to custom_admin_company_proposals_path, notice: "Queued #{proposal_count} #{label} proposal#{'s' unless proposal_count == 1} for review. No company records were published."
    rescue ArgumentError => e
      redirect_to custom_admin_pipeline_run_path(pipeline_run || params[:id]), alert: e.message
    end

    private

    def queue_proposals_for_run(pipeline_run)
      case pipeline_run.run_type
      when CompanyDiscoveryService::RUN_TYPE
        CompanyDiscoveryProposalQueueService.call(pipeline_run: pipeline_run, candidate_indexes: params[:candidate_indexes], admin_user: current_admin_user)
      when AtlasCandidateImportReviewService::RUN_TYPE
        proposals = CompanyProposalQueueService.call(pipeline_run: pipeline_run, candidate_indexes: params[:candidate_indexes], admin_user: current_admin_user)
        proposals.each { |proposal| CompanyProposalEnrichmentService.call(proposal: proposal, admin_user: current_admin_user) }
        proposals
      else
        raise ArgumentError, "This pipeline run does not support candidate proposal queueing"
      end
    end

    def pipeline_runs_scope
      scope = case @activity
              when "agent_reviews" then PipelineRun.where(run_type: AGENT_REVIEW_RUN_TYPES)
              when "import_reviews" then PipelineRun.where(run_type: "atlas_candidate_import_review")
              when "discovery_runs" then PipelineRun.where(run_type: CompanyDiscoveryService::RUN_TYPE)
              when "failed" then PipelineRun.failed
              else PipelineRun.all
              end
      scope = scope.recent
      return scope if @status.blank? || @status == "all"

      scope.where(status: @status)
    end
  end
end
