class SitemapController < ApplicationController
  def index
    @companies = Company.where(visible: true).select(:id, :updated_at).order(updated_at: :desc)
    @categories = Category.where.not(name: "Unknown").where.not(id: [12, 13, 14]).select(:id, :updated_at)
    @statistics_pages = [
      { path: statistics_path, updated_at: Time.current },
      { path: statistics_total_companies_path, updated_at: Time.current },
      { path: statistics_category_evolution_5_years_path, updated_at: Time.current },
      { path: statistics_country_distribution_path, updated_at: Time.current },
      { path: statistics_companies_by_region_path, updated_at: Time.current },
      { path: statistics_tag_distribution_path, updated_at: Time.current },
      { path: statistics_target_client_path, updated_at: Time.current },
      { path: statistics_business_model_path, updated_at: Time.current },
      { path: statistics_ai_trends_path, updated_at: Time.current },
      { path: statistics_funding_by_category_path, updated_at: Time.current },
      { path: statistics_funding_by_region_path, updated_at: Time.current },
      { path: statistics_methodology_path, updated_at: Time.current }
    ]
    @static_pages = [
      { path: root_path, updated_at: Time.current },
      { path: about_path, updated_at: Time.current },
      { path: companies_path, updated_at: Time.current }
    ]

    respond_to do |format|
      format.xml
    end
  end
end
