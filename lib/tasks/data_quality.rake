require "uri"

namespace :data_quality do
  desc "Print a read-only data quality audit for companies"
  task audit: :environment do
    spam_keywords = %w[casino betting porn escort xxx adult]

    normalize_domain = lambda do |url|
      raw = url.to_s.strip.downcase
      next nil if raw.blank? || raw == "unknown"

      raw = "http://#{raw}" unless raw.match?(%r{\Ahttps?://})
      URI.parse(raw).host&.sub(/\Awww\./, "")
    rescue URI::InvalidURIError
      nil
    end

    duplicate_name_groups = Company
      .where.not(name: [nil, ""])
      .group("LOWER(TRIM(name))")
      .having("COUNT(*) > 1")
      .count

    domains = Hash.new { |hash, key| hash[key] = [] }
    Company.where.not(main_url: [nil, ""]).pluck(:id, :main_url).each do |id, main_url|
      domain = normalize_domain.call(main_url)
      domains[domain] << id if domain.present?
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
end
