module Admin
  class AgentReviewsController < BaseController
    def index
      @agent_reviews = PipelineRun.where.not(details: nil).recent.page(params[:page]).per(25)
    end

    def show
      @pipeline_run = PipelineRun.find(params[:id])
      @details = @pipeline_run.details || {}
      @company = Company.find_by(id: @details["company_id"])
      @evidence = Array(@details["evidence"])
      @proposed_corrections = @details["proposed_corrections"] || @details["proposed_changes"] || {}
      @risks = Array(@details["risks"])
    end
  end
end
