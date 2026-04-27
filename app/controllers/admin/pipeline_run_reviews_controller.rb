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

    private

    def pipeline_runs_scope
      scope = PipelineRun.recent
      return scope if @status.blank? || @status == "all"

      scope.where(status: @status)
    end
  end
end
