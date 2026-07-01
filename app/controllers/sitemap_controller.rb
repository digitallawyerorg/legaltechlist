class SitemapController < ApplicationController
  SITEMAP_TAG_MIN_COMPANIES = 5

  def index
    @companies = Company.where(visible: true).select(:id, :slug, :updated_at).order(updated_at: :desc)
    @categories = Category.where.not(name: "Unknown").where.not(id: [12, 13, 14]).select(:id, :slug, :updated_at)
    @business_models = BusinessModel.canonical.select(:id, :slug, :updated_at)
    @target_clients = TargetClient.canonical.select(:id, :slug, :updated_at)
    @tags = sitemap_tags
    @statistics_pages = [
      { path: statistics_path, updated_at: Time.current },
      { path: statistics_total_companies_path, updated_at: Time.current },
      { path: statistics_category_evolution_5_years_path, updated_at: Time.current },
      { path: statistics_country_distribution_path, updated_at: Time.current },
      { path: statistics_tag_distribution_path, updated_at: Time.current },
      { path: statistics_ai_trends_path, updated_at: Time.current },
      { path: statistics_funding_by_category_path, updated_at: Time.current },
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

  private

  def sitemap_tags
    Tag.joins(:companies)
       .where(companies: { visible: true })
       .group("tags.id", "tags.slug", "tags.updated_at")
       .having("COUNT(companies.id) >= ?", SITEMAP_TAG_MIN_COMPANIES)
       .order("COUNT(companies.id) DESC")
       .select("tags.id, tags.slug, tags.updated_at, COUNT(companies.id) AS companies_count")
  end
end
