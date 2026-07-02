class BackfillFoundedDateJob < ApplicationJob
  queue_as :default

  # Runs founded_date backfill off the request thread so it is not bound by the
  # 30s HTTP router timeout. Delegates to CompanyFoundedDateBackfillService, which
  # reuses the same cite-only guard as proposal enrichment.
  def perform(company_id, admin_user_id = nil, force = false)
    company = Company.find_by(id: company_id)
    return unless company

    admin_user = AdminUser.find_by(id: admin_user_id) || Mcp::CuratorActor.admin_user!
    CompanyFoundedDateBackfillService.call(company: company, admin_user: admin_user, force: force)
  rescue StandardError => e
    Rails.logger.debug("[BackfillFoundedDateJob] backfill failed for company #{company_id}: #{e.message}")
  end
end
