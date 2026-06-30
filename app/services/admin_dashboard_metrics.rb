class AdminDashboardMetrics
  CACHE_TTL = 10.minutes

  def self.load
    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) { compute }
  end

  def self.cache_key
    "admin/dashboard_metrics/v1/#{Company.duplicate_candidate_cache_version}"
  end

  def self.compute
    duplicate_domain_ids = Company.duplicate_domain_candidate_ids
    duplicate_name_ids = Company.duplicate_name_candidate_ids

    {
      company_count: Company.count,
      missing_url_count: Company.missing_main_url.count,
      weak_description_count: Company.weak_description.count,
      description_review_count: Company.description_review_candidates.count,
      duplicate_domain_count: duplicate_domain_ids.size,
      duplicate_name_count: duplicate_name_ids.size,
      proposal_review_count: CompanyProposal.pending_review.count,
      pipeline_run_count: PipelineRun.count,
      failed_pipeline_run_count: PipelineRun.failed.count,
      duplicate_domain_ids: duplicate_domain_ids,
      duplicate_name_ids: duplicate_name_ids,
      company_summary_counts: {
        total: Company.count,
        visible: Company.where(visible: true).count,
        hidden: Company.where(visible: false).count,
        missing_url: Company.missing_main_url.count,
        weak_description: Company.weak_description.count,
        duplicate_domain: duplicate_domain_ids.size,
        duplicate_name: duplicate_name_ids.size,
        needs_review: Company.needs_review.count,
        not_reviewed: Company.review_state_not_reviewed.count,
        unknown_taxonomy: unknown_taxonomy_count
      }
    }
  end

  def self.unknown_taxonomy_count
    Company.left_joins(:category, :business_model, :target_client).where(
      "categories.id IS NULL OR categories.name = :unknown OR business_models.id IS NULL OR business_models.name = :unknown OR target_clients.id IS NULL OR target_clients.name = :unknown",
      unknown: "Unknown"
    ).count
  end
  private_class_method :unknown_taxonomy_count
end
