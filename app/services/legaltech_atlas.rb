# frozen_string_literal: true

module LegaltechAtlas
  BASE_URL = "https://legaltechatlas.com"
  COMPANY_PATH_PREFIX = "/companies/"
  SITEMAP_URL = "#{BASE_URL}/sitemap.xml.gz"
  COMPANY_URL_PATTERN = %r{legaltechatlas\.com/companies/([a-z0-9-]+)}i

  module_function

  def slug_for(name)
    name.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/-+/, "-").delete_prefix("-").delete_suffix("-")
  end

  def company_url(slug)
    return nil if slug.blank?

    "#{BASE_URL}#{COMPANY_PATH_PREFIX}#{slug}"
  end

  def parse_company_urls_from_sitemap(xml)
    urls = {}
    xml.to_s.scan(COMPANY_URL_PATTERN) do |match|
      slug = match.is_a?(Array) ? match.first : match
      slug = slug.to_s.downcase
      next if slug.blank?

      urls[slug] = company_url(slug)
    end
    urls
  end

  def fetch_sitemap_company_urls
    require "net/http"
    require "zlib"
    require "stringio"

    response = Net::HTTP.get_response(URI(SITEMAP_URL))
    raise "LegalTechAtlas sitemap request failed with #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    body = response.body
    body = Zlib::GzipReader.new(StringIO.new(body)).read if response["content-type"].to_s.include?("gzip") || body.start_with?("\x1F\x8B".b)
    parse_company_urls_from_sitemap(body)
  end
end
