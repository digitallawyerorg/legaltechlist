module Admin
  class AppController < BaseController
    def show
      @company_count = Company.count
      @missing_url_count = Company.missing_main_url.count
      @weak_description_count = Company.weak_description.count
      @duplicate_domain_count = Company.duplicate_domain_candidate_ids.count
      @pipeline_run_count = PipelineRun.count
    end
  end
end
