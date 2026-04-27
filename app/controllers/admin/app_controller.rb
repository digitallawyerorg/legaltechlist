module Admin
  class AppController < BaseController
    def show
      @company_count = Company.count
      @missing_url_count = Company.missing_main_url.count
      @weak_description_count = Company.weak_description.count
      @description_review_count = Company.description_review_candidates.count
      @duplicate_domain_count = Company.duplicate_domain_candidate_ids.count
      @duplicate_name_count = Company.duplicate_name_candidate_ids.count
      @proposal_review_count = CompanyProposal.pending_review.count
      @pipeline_run_count = PipelineRun.count
      @failed_pipeline_run_count = PipelineRun.failed.count
      @recent_pipeline_runs = PipelineRun.recent.limit(5)
      @recent_agent_reviews = PipelineRun.where(run_type: ["company_agent_review", "duplicate_domain_review"]).recent.limit(5)
      @recent_candidate_imports = PipelineRun.where(run_type: "atlas_candidate_import_review").recent.limit(3)
    end
  end
end
