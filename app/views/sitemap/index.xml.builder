xml.instruct! :xml, version: "1.0", encoding: "UTF-8"
xml.urlset xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9" do
  @static_pages.each do |page|
    xml.url do
      xml.loc "#{site_url}#{page[:path]}"
      xml.lastmod page[:updated_at].to_date.iso8601
      xml.changefreq "weekly"
      xml.priority page[:path] == root_path ? "1.0" : "0.8"
    end
  end

  @statistics_pages.each do |page|
    xml.url do
      xml.loc "#{site_url}#{page[:path]}"
      xml.lastmod page[:updated_at].to_date.iso8601
      xml.changefreq "weekly"
      xml.priority "0.7"
    end
  end

  @categories.each do |category|
    xml.url do
      xml.loc "#{site_url}#{category_path(category)}"
      xml.lastmod category.updated_at.to_date.iso8601
      xml.changefreq "weekly"
      xml.priority "0.6"
    end
  end

  @business_models.each do |business_model|
    xml.url do
      xml.loc "#{site_url}#{business_model_path(business_model)}"
      xml.lastmod business_model.updated_at.to_date.iso8601
      xml.changefreq "weekly"
      xml.priority "0.55"
    end
  end

  @target_clients.each do |target_client|
    xml.url do
      xml.loc "#{site_url}#{target_client_path(target_client)}"
      xml.lastmod target_client.updated_at.to_date.iso8601
      xml.changefreq "weekly"
      xml.priority "0.55"
    end
  end

  @tags.each do |tag|
    xml.url do
      xml.loc "#{site_url}#{tag_path(tag)}"
      xml.lastmod tag.updated_at.to_date.iso8601
      xml.changefreq "weekly"
      xml.priority "0.5"
    end
  end

  @companies.find_each do |company|
    xml.url do
      xml.loc "#{site_url}#{company_path(company)}"
      xml.lastmod company.updated_at.to_date.iso8601
      xml.changefreq "monthly"
      xml.priority "0.5"
    end
  end
end
