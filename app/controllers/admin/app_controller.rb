module Admin
  class AppController < BaseController
    def show
      metrics = AdminDashboardMetrics.load
      @company_count = metrics[:company_count]
      @missing_url_count = metrics[:missing_url_count]
      @weak_description_count = metrics[:weak_description_count]
      @description_review_count = metrics[:description_review_count]
      @duplicate_domain_count = metrics[:duplicate_domain_count]
      @duplicate_name_count = metrics[:duplicate_name_count]
      @proposal_review_count = metrics[:proposal_review_count]
      @pipeline_run_count = metrics[:pipeline_run_count]
      @failed_pipeline_run_count = metrics[:failed_pipeline_run_count]
      @recent_pipeline_runs = PipelineRun.recent.limit(5)
      @recent_agent_reviews = PipelineRun.where(run_type: ["company_agent_review", "duplicate_domain_review"]).recent.limit(5)
      @recent_candidate_imports = PipelineRun.where(run_type: "atlas_candidate_import_review").recent.limit(3)
    end
  end
end
