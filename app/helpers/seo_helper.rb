module SeoHelper
  SITE_NAME = "CodeX TechIndex".freeze
  DEFAULT_DESCRIPTION = "Explore the CodeX TechIndex — a curated database of legal technology companies with ecosystem statistics, funding data, and research insights from Stanford CodeX.".freeze
  DEFAULT_SITE_URL = "https://techindex.law.stanford.edu".freeze

  def site_url
    ENV.fetch("SITE_URL", DEFAULT_SITE_URL)
  end

  def seo_page_title
    content_for?(:title) ? content_for(:title) : SITE_NAME
  end

  def seo_full_title
    content_for?(:title) ? "#{content_for(:title)} | #{SITE_NAME}" : SITE_NAME
  end

  def seo_description
    content_for?(:description) ? content_for(:description) : DEFAULT_DESCRIPTION
  end

  def canonical_url
    content_for?(:canonical) ? content_for(:canonical) : "#{site_url}#{request.path}"
  end

  def paginated_page_url(page)
    params = request.query_parameters.symbolize_keys
    page_number = page.to_i
    params = page_number > 1 ? params.merge(page: page_number) : params.except(:page)
    query = params.to_query
    query.present? ? "#{site_url}#{request.path}?#{query}" : "#{site_url}#{request.path}"
  end

  def pagination_rel_link(page, rel)
    return unless page

    tag.link(rel: rel, href: paginated_page_url(page))
  end

  def google_analytics_id
    ENV["GOOGLE_ANALYTICS_ID"].presence || ENV["GA_MEASUREMENT_ID"].presence
  end

  def website_json_ld
    {
      "@context" => "https://schema.org",
      "@type" => "WebSite",
      "name" => SITE_NAME,
      "url" => site_url,
      "description" => DEFAULT_DESCRIPTION,
      "publisher" => {
        "@type" => "Organization",
        "name" => "CodeX, Stanford Center for Legal Informatics",
        "url" => "https://law.stanford.edu/codex-the-stanford-center-for-legal-informatics/"
      }
    }.to_json
  end

  def dataset_json_ld(name:, description:, url:)
    {
      "@context" => "https://schema.org",
      "@type" => "Dataset",
      "name" => name,
      "description" => description,
      "url" => url,
      "creator" => {
        "@type" => "Organization",
        "name" => "CodeX, Stanford Center for Legal Informatics"
      },
      "dateModified" => Date.current.iso8601,
      "license" => "#{site_url}/about/data"
    }.to_json
  end

  def item_list_json_ld(name:, description:, url:, items:)
    {
      "@context" => "https://schema.org",
      "@type" => "ItemList",
      "name" => name,
      "description" => description,
      "url" => url,
      "numberOfItems" => items.size,
      "itemListElement" => items.each_with_index.map do |item, index|
        {
          "@type" => "ListItem",
          "position" => index + 1,
          "name" => item[:name],
          "url" => item[:url]
        }
      end
    }.to_json
  end

  def company_organization_json_ld(company)
    data = {
      "@context" => "https://schema.org",
      "@type" => "Organization",
      "name" => company.name,
      "url" => company.main_url.presence || company_url(company)
    }
    data["description"] = company.description if company.description.present?
    data["foundingDate"] = company.founded_date if company.founded_date.present? && company.founded_date.match?(/^\d{4}$/)
    data["address"] = company.location if company.location.present?
    data.to_json
  end

  def statistics_index_json_ld
    items = [
      { name: "Total Companies", url: statistics_total_companies_url },
      { name: "Geographic Distribution", url: statistics_country_distribution_url },
      { name: "Industry Focus", url: statistics_category_evolution_5_years_url },
      { name: "Technology Themes", url: statistics_tag_distribution_url },
      { name: "Market Focus", url: statistics_target_client_url },
      { name: "AI in Legal Tech", url: statistics_ai_trends_url },
      { name: "Funding", url: statistics_funding_by_category_url },
      { name: "Venture Stage", url: statistics_venture_stage_url },
      { name: "Revenue Model Insights", url: statistics_business_model_url }
    ]
    item_list_json_ld(
      name: "CodeX TechIndex Statistics",
      description: "Research dashboards covering legal tech ecosystem growth, geography, funding, and market segments.",
      url: statistics_url,
      items: items
    )
  end
end
