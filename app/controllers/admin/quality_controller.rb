module Admin
  class QualityController < BaseController
    def index
      @company_metrics = [
        { label: "Total companies", value: Company.count, tone: "primary" },
        { label: "Public companies", value: Company.publicly_visible.count, tone: "success" },
        { label: "Missing URLs", value: Company.missing_main_url.count, tone: "warning" },
        { label: "Weak descriptions", value: Company.weak_description.count, tone: "warning" },
        { label: "Duplicate-name candidates", value: Company.duplicate_name_candidate_ids.count, tone: "danger" },
        { label: "Duplicate-domain candidates", value: Company.duplicate_domain_candidate_ids.count, tone: "danger" },
        { label: "Unknown category", value: Company.unknown_category.count, tone: "warning" },
        { label: "Unknown revenue model", value: Company.unknown_business_model.count, tone: "warning" },
        { label: "Unknown target client", value: Company.unknown_target_client.count, tone: "warning" }
      ]

      @review_metrics = [
        { label: "Not reviewed", value: Company.review_state_not_reviewed.count, tone: "secondary" },
        { label: "Needs review", value: Company.review_state_in_review.count, tone: "warning" },
        { label: "Verified", value: Company.review_state_verified.count, tone: "success" },
        { label: "Rejected", value: Company.review_state_rejected.count, tone: "danger" },
        { label: "Human reviewed", value: Company.human_reviewed.count, tone: "info" }
      ]

      @pipeline_metrics = [
        { label: "Pipeline runs", value: PipelineRun.count, tone: "primary" },
        { label: "Running", value: PipelineRun.running.count, tone: "info" },
        { label: "Failed", value: PipelineRun.failed.count, tone: "danger" }
      ]
    end
  end
end
