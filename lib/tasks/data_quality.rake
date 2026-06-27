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
        company.update!(location: normalized)
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
end
