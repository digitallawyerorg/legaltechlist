# frozen_string_literal: true

module LegaltechAtlas
  BASE_URL = "https://legaltechatlas.com"
  COMPANY_PATH_PREFIX = "/companies/"
  SITEMAP_URL = "#{BASE_URL}/sitemap.xml.gz"
  SYNC_URL = ENV.fetch("LEGALTECH_ATLAS_SYNC_URL", "#{BASE_URL}/companies/sync.json")
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

  def fetch_companies_index(url: SYNC_URL, token: ENV["TECHINDEX_SYNC_TOKEN"])
    require "net/http"
    require "json"

    uri = URI(url)
    request = Net::HTTP::Get.new(uri)
    request["Accept"] = "application/json"
    request["X-TechIndex-Sync-Token"] = token if token.present?

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: 15, read_timeout: 60) do |http|
      http.request(request)
    end
    raise "LegalTechAtlas sync API failed with #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    payload = JSON.parse(response.body)
    raise "LegalTechAtlas sync API returned unexpected payload" unless payload.is_a?(Array)

    payload
  end
end
