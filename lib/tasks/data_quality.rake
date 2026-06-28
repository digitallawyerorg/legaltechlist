namespace :data_quality do
  desc "Print a read-only data quality audit for companies"
  task audit: :environment do
    spam_keywords = %w[casino betting porn escort xxx adult]

    duplicate_name_groups = Company
      .where.not(name: [nil, ""])
      .group("LOWER(TRIM(name))")
      .having("COUNT(*) > 1")
      .count

    domains = Hash.new { |hash, key| hash[key] = [] }
    if Company.column_names.include?("canonical_domain")
      Company.where.not(main_url: [nil, ""]).pluck(:id, :main_url, :canonical_domain).each do |id, main_url, canonical_domain|
        domain = canonical_domain.presence || Company.canonical_domain_for(main_url)
        domains[domain] << id if domain.present?
      end
    else
      Company.where.not(main_url: [nil, ""]).pluck(:id, :main_url).each do |id, main_url|
        domain = Company.canonical_domain_for(main_url)
        domains[domain] << id if domain.present?
      end
    end
    duplicate_domain_groups = domains.select { |_domain, ids| ids.size > 1 }

    spam_counts = spam_keywords.to_h do |keyword|
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(keyword)}%"
      count = Company.where(
        "LOWER(COALESCE(name, '') || ' ' || COALESCE(description, '') || ' ' || COALESCE(main_url, '')) LIKE ?",
        pattern
      ).count

      [keyword, count]
    end

    metrics = {
      total_companies: Company.count,
      visible_companies: Company.where(visible: true).count,
      invisible_companies: Company.where(visible: false).count,
      missing_main_url: Company.where(main_url: [nil, ""]).count,
      missing_category: Company.where(category_id: nil).count,
      missing_business_model: Company.where(business_model_id: nil).count,
      missing_target_client: Company.where(target_client_id: nil).count,
      weak_description: Company.where("description IS NULL OR LENGTH(TRIM(description)) < 40").count,
      stale_records: Company.where("updated_at < ?", 2.years.ago).count,
      duplicate_name_groups: duplicate_name_groups.size,
      duplicate_name_records: duplicate_name_groups.values.sum,
      duplicate_domain_groups: duplicate_domain_groups.size,
      duplicate_domain_records: duplicate_domain_groups.values.sum(&:size)
    }

    puts "TechIndex data quality audit"
    puts "Generated at: #{Time.current.utc.iso8601}"
    puts "Mode: read-only"
    puts

    metrics.each do |key, value|
      puts "#{key}: #{value}"
    end

    puts
    puts "spam_keyword_matches:"
    spam_counts.each do |keyword, count|
      puts "  #{keyword}: #{count}"
    end

    puts
    puts "top_duplicate_names:"
    duplicate_name_groups.first(10).each do |name, count|
      puts "  #{name}: #{count}"
    end

    puts
    puts "top_duplicate_domains:"
    duplicate_domain_groups.first(10).each do |domain, ids|
      puts "  #{domain}: #{ids.size}"
    end
  end

  desc "Backfill company fingerprint and canonical domain fields. Defaults to dry-run; set DRY_RUN=false to write."
  task backfill_identity: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    verbose = ENV.fetch("VERBOSE", "false") == "true"
    changed = 0
    examples = []

    Company.find_each do |company|
      canonical_domain = company.canonical_main_domain
      fingerprint = company.calculated_fingerprint
      next if company.canonical_domain == canonical_domain && company.fingerprint == fingerprint

      changed += 1
      if dry_run
        line = "DRY RUN company_id=#{company.id} canonical_domain=#{canonical_domain.inspect} fingerprint=#{fingerprint.inspect}"
        verbose ? puts(line) : examples << line if examples.size < 10
      else
        company.update_columns(
          canonical_domain: canonical_domain,
          fingerprint: fingerprint,
          updated_at: company.updated_at
        )
      end
    end

    mode = dry_run ? "dry-run" : "write"
    puts examples if dry_run && !verbose
    puts "Backfill identity complete mode=#{mode} changed=#{changed}"
  end

  desc "Normalize company locations missing country names. Defaults to dry-run; set DRY_RUN=false to write."
  task normalize_locations: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    verbose = ENV.fetch("VERBOSE", "false") == "true"
    category_id = ENV["CATEGORY_ID"]
    changed = 0
    still_missing_flag = 0
    examples = []

    scope = Company.all
    scope = scope.where(category_id: category_id) if category_id.present?

    scope.find_each do |company|
      next if company.location.blank?

      normalized = LocationCountryResolver.format_for_display(company.location)
      next if normalized.blank? || normalized == company.location

      changed += 1
      if dry_run
        line = "DRY RUN company_id=#{company.id} #{company.location.inspect} -> #{normalized.inspect}"
        verbose ? puts(line) : examples << line if examples.size < 20
      else
        company.update_columns(location: normalized, updated_at: Time.current)
      end
    end

    flag_scope = scope.where.not(location: [nil, ""])
    flag_scope.find_each do |company|
      still_missing_flag += 1 if LocationCountryResolver.iso_code_for(company.location).blank?
    end

    mode = dry_run ? "dry-run" : "write"
    puts examples if dry_run && !verbose
    puts "Normalize locations complete mode=#{mode} category_id=#{category_id || 'all'} changed=#{changed} still_missing_flag=#{still_missing_flag}"
  end

  desc "Backfill structured country and city fields from location text. Defaults to dry-run; set DRY_RUN=false to write."
  task backfill_location_fields: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    overwrite = ENV.fetch("OVERWRITE", "false") == "true"
    verbose = ENV.fetch("VERBOSE", "false") == "true"
    category_id = ENV["CATEGORY_ID"]
    applied = 0
    skipped = Hash.new(0)
    examples = []

    scope = Company.all
    scope = scope.where(category_id: category_id) if category_id.present?

    total = scope.count
    resolved = 0

    scope.find_each do |company|
      result = CompanyLocationBackfillService.call(company: company, dry_run: dry_run, overwrite: overwrite)
      action = result["action"]
      if action == "applied" || action == "would_apply"
        applied += 1
        resolved += 1 if result["country"].present?
        if dry_run && verbose
          puts "DRY RUN company_id=#{company.id} country=#{result['country'].inspect} city=#{result['city'].inspect}"
        elsif dry_run && examples.size < 20
          examples << "DRY RUN company_id=#{company.id} country=#{result['country'].inspect} city=#{result['city'].inspect}"
        end
      else
        skipped[action] += 1
      end
    end

    with_location = scope.where.not(location: [nil, ""]).count
    country_rate = with_location.positive? ? ((resolved.to_f / with_location) * 100).round(1) : 0.0

    mode = dry_run ? "dry-run" : "write"
    puts examples if dry_run && !verbose
    puts "Backfill location fields complete mode=#{mode} category_id=#{category_id || 'all'} total=#{total} applied=#{applied} country_resolution_rate=#{country_rate}% skipped=#{skipped.sort.to_h}"
  end

  # Locations corrupted by an earlier normalize_locations run before small-country ISO codes existed.
  CORRUPTED_LOCATION_FIXES = {
    "https://www.crunchbase.com/organization/korporatio" => "Victoria, Seychelles",
    "https://www.crunchbase.com/organization/legaltechnology-hub" => "New York, Honduras"
  }.freeze

  LEGAL_ENTITY_SUFFIX_PATTERN = /
    \s+
    (?:
      O[Üü] |
      GmbH |
      AG |
      S\.?A\.? |
      B\.?V\.? |
      Oy |
      LLC |
      LLP |
      LTD\.? |
      LIMITED |
      PRIVATE\s+LIMITED |
      CO\.?\s+LTD\.?
    )
    \z
  /ix.freeze

  desc "List company names ending with legal entity suffixes (OÜ, Ltd, GmbH, etc.). Read-only."
  task audit_legal_entity_names: :environment do
    visible_only = ENV.fetch("VISIBLE_ONLY", "false") == "true"
    scope = visible_only ? Company.where(visible: true) : Company.all
    matches = scope.where.not(name: [nil, ""]).select { |company| company.name.match?(LEGAL_ENTITY_SUFFIX_PATTERN) }

    puts "Legal entity suffix audit"
    puts "Generated at: #{Time.current.utc.iso8601}"
    puts "Mode: read-only"
    puts "visible_only: #{visible_only}"
    puts "matches: #{matches.size}"
    puts

    matches.sort_by(&:id).each do |company|
      puts [
        company.id,
        company.visible ? "visible" : "hidden",
        company.name,
        company.description.to_s[0, 80].gsub(/\s+/, " ")
      ].join(" | ")
    end
  end

  desc "Revert known corrupted company locations. Defaults to dry-run; set DRY_RUN=false to write."
  task fix_corrupted_locations: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    verbose = ENV.fetch("VERBOSE", "false") == "true"
    changed = 0
    examples = []

    CORRUPTED_LOCATION_FIXES.each do |crunchbase_url, correct_location|
      company = Company.find_by(crunchbase_url: crunchbase_url)
      next if company.blank? || company.location.blank?
      next if company.location == correct_location

      changed += 1
      if dry_run
        line = "DRY RUN company_id=#{company.id} #{company.location.inspect} -> #{correct_location.inspect}"
        verbose ? puts(line) : examples << line
      else
        company.update_columns(location: correct_location, updated_at: Time.current)
      end
    end

    mode = dry_run ? "dry-run" : "write"
    puts examples if dry_run && !verbose
    puts "Fix corrupted locations complete mode=#{mode} changed=#{changed}"
  end

  desc "Fix legal-entity company names and hide consultancy profiles. Defaults to dry-run; set DRY_RUN=false to write."
  task fix_brand_names: :environment do
    require Rails.root.join("lib/company_brand_name_fixer")

    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    verbose = ENV.fetch("VERBOSE", "false") == "true"
    hidden = 0
    renamed = 0
    changes = []

    Company.where(visible: true).find_each do |company|
      next unless CompanyBrandNameFixer.legal_entity_caps?(company) ||
                  CompanyBrandNameFixer.mixed_case_legal_suffix?(company) ||
                  CompanyBrandNameFixer.consultancy?(company)

      result = CompanyBrandNameFixer.review_company(company)
      next if result[:action] == :skip

      case result[:action]
      when :hide
        hidden += 1
        line = "HIDE|#{company.id}|#{company.name}|removed/hidden|#{result[:reason]}"
        changes << line
        puts(line) if verbose
        CompanyBrandNameFixer.apply!(company, result, dry_run: dry_run) unless dry_run
      when :rename
        renamed += 1
        line = "RENAME|#{company.id}|#{company.name}|#{result[:new_name]}|#{result[:reason]}"
        changes << line
        puts(line) if verbose
        CompanyBrandNameFixer.apply!(company, result, dry_run: dry_run) unless dry_run
      end
    end

    changes.each { |line| puts line } unless verbose
    mode = dry_run ? "dry-run" : "write"
    puts "Fix brand names complete mode=#{mode} hidden=#{hidden} renamed=#{renamed} total=#{hidden + renamed}"
  end
end
