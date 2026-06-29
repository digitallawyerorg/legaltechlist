class LegaltechAtlasLinkSyncJob < ApplicationJob
  queue_as :default

  def perform(company_id)
    company = Company.find_by(id: company_id)
    return unless company

    LegaltechAtlasLinkSyncService.sync_one(company, dry_run: false)
  rescue StandardError => e
    Rails.logger.debug { "LegaltechAtlas link sync job failed for company_id=#{company_id}: #{e.message}" }
  end
end
