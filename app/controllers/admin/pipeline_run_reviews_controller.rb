module Admin
  class PipelineRunReviewsController < BaseController
    def index
      @status = params[:status].presence
      @pipeline_runs = pipeline_runs_scope.page(params[:page]).per(25)
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
      proposals = CompanyProposalQueueService.call(pipeline_run: pipeline_run, candidate_indexes: params[:candidate_indexes], admin_user: current_admin_user)
      proposals.each { |proposal| CompanyProposalEnrichmentService.call(proposal: proposal, admin_user: current_admin_user) }

      redirect_to custom_admin_company_proposals_path, notice: "Queued and enriched #{proposals.size} candidate proposal#{'s' unless proposals.size == 1}. No company records were changed."
    rescue ArgumentError => e
      redirect_to custom_admin_pipeline_run_path(pipeline_run || params[:id]), alert: e.message
    end

    private

    def pipeline_runs_scope
      scope = PipelineRun.recent
      return scope if @status.blank? || @status == "all"

      scope.where(status: @status)
    end
  end
end
