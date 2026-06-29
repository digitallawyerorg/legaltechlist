class CompanyLogoFetchJob < ApplicationJob
  queue_as :default

  def perform(company_id)
    company = Company.find_by(id: company_id)
    return unless company&.logo_fetch_needed?

    LogoFetcherService.fetch_for_company(company)
  end
end
