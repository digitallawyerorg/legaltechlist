# frozen_string_literal: true

require "csv"

class LegaltechAtlasLinkSyncService
  Result = Struct.new(
    :matched,
    :updated,
    :cleared,
    :skipped,
    :unmatched_csv_rows,
    :examples,
    keyword_init: true
  )

  def self.call(source: :api, file: nil, dry_run: true, clear_missing: false, scope: Company.all, sitemap_index: nil, api_index: nil)
    new(source: source, file: file, dry_run: dry_run, clear_missing: clear_missing, scope: scope, sitemap_index: sitemap_index, api_index: api_index).call
  end

  def self.sync_one(company, dry_run: false)
    call(source: :api, dry_run: dry_run, scope: Company.where(id: company.id))
  end

  def initialize(source: :api, file: nil, dry_run: true, clear_missing: false, scope: Company.all, sitemap_index: nil, api_index: nil)
    @source = source.to_sym
    @file = file
    @dry_run = dry_run
    @clear_missing = clear_missing
    @scope = scope
    @sitemap_index = sitemap_index
    @api_index = api_index
  end

  def call
    atlas_urls_by_company_id = build_matches
    matched_company_ids = atlas_urls_by_company_id.keys
    updated = 0
    cleared = 0
    examples = []

    @scope.find_each do |company|
      atlas_url = atlas_urls_by_company_id[company.id]
      if atlas_url.present?
        next if company.legaltech_atlas_url == atlas_url

        updated += 1
        examples << "SET company_id=#{company.id} #{company.name.inspect} -> #{atlas_url}" if examples.size < 20
        company.update_columns(legaltech_atlas_url: atlas_url, updated_at: Time.current) unless @dry_run
      elsif @clear_missing && company.legaltech_atlas_url.present?
        cleared += 1
        examples << "CLEAR company_id=#{company.id} #{company.name.inspect}" if examples.size < 20
        company.update_columns(legaltech_atlas_url: nil, updated_at: Time.current) unless @dry_run
      end
    end

    Result.new(
      matched: matched_company_ids.size,
      updated: updated,
      cleared: cleared,
      skipped: @scope.count - matched_company_ids.size,
      unmatched_csv_rows: @unmatched_csv_rows || 0,
      examples: examples
    )
  end

  private

  def build_matches
    case @source
    when :api
      build_matches_from_api
    when :csv
      build_matches_from_csv
    when :sitemap
      build_matches_from_sitemap
    else
      raise ArgumentError, "Unsupported source #{@source.inspect}. Use :api, :csv, or :sitemap."
    end
  end

  def build_matches_from_api
    records = @api_index || LegaltechAtlas.fetch_companies_index
    lookups = build_api_lookups(records)
    atlas_urls_by_company_id = {}

    @scope.where.not(name: [nil, ""]).find_each do |company|
      atlas_url = match_company_from_api_lookups(company, lookups)
      atlas_urls_by_company_id[company.id] = atlas_url if atlas_url.present?
    end

    atlas_urls_by_company_id
  end

  def build_api_lookups(records)
    {
      domain: unique_lookup(records) { |record| canonical_domain_from_api_record(record) },
      name: unique_lookup(records) { |record| normalized_name_from_api_record(record) },
      slug: unique_lookup(records) { |record| slug_from_api_record(record) }
    }
  end

  def match_company_from_api_lookups(company, lookups)
    domain = company.canonical_domain.presence || company.canonical_main_domain
    if domain.present?
      atlas_url = lookups[:domain][domain]
      return atlas_url if atlas_url.present?
    end

    normalized_name = company.normalized_name
    if normalized_name.present?
      atlas_url = lookups[:name][normalized_name]
      return atlas_url if atlas_url.present?
    end

    slug = LegaltechAtlas.slug_for(company.name)
    lookups[:slug][slug]
  end

  def unique_lookup(records)
    index = {}
    ambiguous = {}

    records.each do |record|
      key = yield(record)
      next if key.blank?

      atlas_url = normalized_atlas_url(record["atlas_url"])
      next if atlas_url.blank?

      if index.key?(key)
        ambiguous[key] = true
      else
        index[key] = atlas_url
      end
    end

    ambiguous.each_key { |key| index.delete(key) }
    index
  end

  def canonical_domain_from_api_record(record)
    domain = record["canonical_domain"].presence || Company.canonical_domain_for(record["website"] || record["website_url"])
    domain.presence
  end

  def normalized_name_from_api_record(record)
    Company.normalized_name_value(record["name"])
  end

  def slug_from_api_record(record)
    record["slug"].to_s.downcase.presence
  end

  def build_matches_from_csv
    raise ArgumentError, "CSV file path is required when source=csv" if @file.blank?

    path = Pathname.new(@file)
    raise ArgumentError, "CSV file not found: #{path}" unless path.file?

    atlas_urls_by_company_id = {}
    @unmatched_csv_rows = 0

    CSV.foreach(path, headers: true) do |row|
      atlas_url = normalized_atlas_url(row["atlas_url"] || row["Atlas URL"] || row["legaltech_atlas_url"])
      next if atlas_url.blank?

      company = find_company_for_row(row)
      if company
        atlas_urls_by_company_id[company.id] = atlas_url
      else
        @unmatched_csv_rows += 1
        Rails.logger.debug { "LegaltechAtlasLinkSyncService unmatched CSV row atlas_url=#{atlas_url}" }
      end
    end

    atlas_urls_by_company_id
  end

  def build_matches_from_sitemap
    slug_index = @sitemap_index || LegaltechAtlas.fetch_sitemap_company_urls
    atlas_urls_by_company_id = {}

    @scope.where.not(name: [nil, ""]).find_each do |company|
      slug = LegaltechAtlas.slug_for(company.name)
      atlas_url = slug_index[slug]
      atlas_urls_by_company_id[company.id] = atlas_url if atlas_url.present?
    end

    atlas_urls_by_company_id
  end

  def find_company_for_row(row)
    domain = canonical_domain_from_row(row)
    if domain.present?
      company = find_company_by_domain(domain)
      return company if company
    end

    name = row["name"] || row["Name"] || row["organization_name"] || row["Organization Name"]
    return nil if name.blank?

    normalized_name = Company.normalized_name_value(name)
    return nil if normalized_name.blank?

    @scope.where.not(name: [nil, ""]).find { |company| company.normalized_name == normalized_name }
  end

  def find_company_by_domain(domain)
    @scope.where(canonical_domain: domain).first ||
      @scope.where.not(main_url: [nil, ""]).find { |company| (company.canonical_domain.presence || company.canonical_main_domain) == domain }
  end

  def canonical_domain_from_row(row)
    domain = row["domain"] || row["Domain"] || row["canonical_domain"]
    return Company.canonical_domain_for(domain) if domain.present?

    website = row["website"] || row["Website"] || row["main_url"]
    Company.canonical_domain_for(website)
  end

  def normalized_atlas_url(url)
    value = url.to_s.strip
    return nil if value.blank?
    return nil unless value.match?(%r{\Ahttps?://legaltechatlas\.com/companies/[a-z0-9-]+\z}i)

    value.sub(%r{\Ahttp://}i, "https://").downcase
  end
end
