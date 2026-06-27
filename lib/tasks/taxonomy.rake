namespace :taxonomy do
  desc "Seed canonical revenue models from MethodologyHelper. Set DRY_RUN=false to write."
  task seed_revenue_models: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"

    MethodologyHelper::REVENUE_MODELS.each do |row|
      existing = BusinessModel.find_by(name: row[:name])
      if existing
        puts "exists #{row[:name]}"
        next
      end

      if dry_run
        puts "DRY RUN create #{row[:name]}"
      else
        BusinessModel.create!(name: row[:name], description: row[:definition])
        puts "created #{row[:name]}"
      end
    end

    puts "seed_revenue_models complete mode=#{dry_run ? 'dry-run' : 'write'}"
  end

  desc "Map legacy business model names to canonical revenue models. Set DRY_RUN=false to write."
  task normalize_revenue_models: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    mappings = {
      "SaaS" => ["Subscription"],
      "Publishing" => ["Licensing"],
      "Content Provider" => ["Licensing"],
      "Data & Analytics" => ["Subscription"],
      "Data" => ["Subscription"],
      "Managed Service" => ["Services"],
      "Legal Tech" => ["Subscription"],
      "Legal Service Using Tech" => ["Services", "Subscription"],
      "Legal Service" => ["Services"],
      "Marketplace" => ["Transaction Fee", "Subscription"],
      "Government" => ["Grants & Subsidies"],
      "Knowledge & Research" => ["Licensing"],
      "Practice Management" => ["Subscription"],
      "Marketplace and ALSPs" => ["Transaction Fee", "Subscription"]
    }

    Company.find_each do |company|
      legacy_names = company.revenue_models.map(&:name).uniq
      target_names = legacy_names.flat_map { |name| mappings.fetch(name, [name]) }.uniq
      target_names = target_names & MethodologyHelper::REVENUE_MODEL_NAMES
      target_names = ["Other"] if target_names.empty?
      records = target_names.filter_map { |name| BusinessModel.find_by(name: name) }.uniq
      next if records.map(&:id).sort == company.business_model_ids.sort

      line = "company_id=#{company.id} #{legacy_names.inspect} -> #{records.map(&:name).inspect}"
      if dry_run
        puts "DRY RUN #{line}"
      else
        company.business_model_ids = records.map(&:id)
        company.save!(validate: false)
        puts line
      end
    end

    puts "normalize_revenue_models complete mode=#{dry_run ? 'dry-run' : 'write'}"
  end

  desc "Retire Data revenue model (maps to Subscription). Set DRY_RUN=false to write."
  task retire_data_revenue_model: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    data_model = BusinessModel.find_by(name: "Data")
    subscription = BusinessModel.find_by(name: "Subscription")
    return puts "no Data model to retire" unless data_model
    return puts "Subscription model required" unless subscription

    CompanyBusinessModel.where(business_model_id: data_model.id).find_each do |join|
      next if CompanyBusinessModel.exists?(company_id: join.company_id, business_model_id: subscription.id)

      line = "company_id=#{join.company_id} Data -> Subscription"
      if dry_run
        puts "DRY RUN #{line}"
      else
        CompanyBusinessModel.create!(company_id: join.company_id, business_model_id: subscription.id)
        puts line
      end
    end

    if dry_run
      puts "DRY RUN would delete Data model id=#{data_model.id}" if CompanyBusinessModel.where(business_model_id: data_model.id).none?
    else
      CompanyBusinessModel.where(business_model_id: data_model.id).delete_all
      data_model.destroy! if CompanyBusinessModel.where(business_model_id: data_model.id).none?
      puts "retired Data revenue model"
    end
  end

  desc "Backfill revenue models for companies. DRY_RUN=false to write. LIMIT=N optional."
  task backfill_revenue_models: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    limit = ENV["LIMIT"]&.to_i
    min_confidence = ENV.fetch("MIN_CONFIDENCE", CompanyRevenueModelBackfillService::HIGH_CONFIDENCE.to_s).to_f
    overwrite_unknown_only = ENV.fetch("OVERWRITE_UNKNOWN_ONLY", "true") != "false"
    overwrite_other_only = ENV.fetch("OVERWRITE_OTHER_ONLY", "false") != "false"
    scope = Company.publicly_visible.includes(:business_models, :tags, :category, :target_client).order(:id)
    scope = scope.joins(:company_business_models).where(company_business_models: { business_model_id: BusinessModel.find_by(name: "Other")&.id }).distinct if overwrite_other_only
    scope = scope.limit(limit) if limit.present?

    counts = Hash.new(0)
    scope.find_each do |company|
      result = CompanyRevenueModelBackfillService.call(
        company: company,
        dry_run: dry_run,
        min_confidence: min_confidence,
        overwrite_unknown_only: overwrite_unknown_only,
        overwrite_other_only: overwrite_other_only
      )
      counts[result["action"]] += 1
      next unless result["action"].in?(%w[would_apply applied needs_review])

      puts [
        result["action"],
        "company_id=#{company.id}",
        result["current_revenue_models"].inspect,
        "->",
        result["suggested_revenue_models"].inspect,
        "confidence=#{result['confidence']}"
      ].join(" ")
    end

    puts "backfill_revenue_models complete mode=#{dry_run ? 'dry-run' : 'write'} counts=#{counts.inspect}"
  end

  desc "Print taxonomy health metrics (read-only)."
  task audit: :environment do
    canonical_revenue = MethodologyHelper::REVENUE_MODEL_NAMES
    non_canonical_revenue = BusinessModel.where.not(name: canonical_revenue + ["Unknown"]).pluck(:name).uniq.sort

    puts "TechIndex taxonomy audit"
    puts "Generated at: #{Time.current.utc.iso8601}"
    puts
    puts "companies_total: #{Company.count}"
    puts "companies_visible: #{Company.publicly_visible.count}"
    puts "unknown_category: #{Company.unknown_category.count}"
    puts "unknown_target_client: #{Company.unknown_target_client.count}"
    puts "unknown_revenue_model: #{Company.joins(company_business_models: :business_model).where(business_models: { name: 'Unknown' }).distinct.count}"
    puts "legacy_unknown_revenue_fk: #{Company.joins(:business_model).where(business_models: { name: 'Unknown' }).count}"
    puts "no_m2m_revenue: #{Company.left_joins(:company_business_models).where(company_business_models: { id: nil }).where(business_model_id: nil).count}"
    puts "untagged_visible: #{Company.publicly_visible.left_joins(:taggings).where(taggings: { id: nil }).count}"
    puts "categories: #{Category.order(:name).pluck(:name).join(', ')}"
    puts "target_clients: #{TargetClient.count}"
    puts "tags: #{Tag.count}"
    puts
    puts "non_canonical_revenue_models (#{non_canonical_revenue.size}):"
    non_canonical_revenue.each { |name| puts "  #{name}" }
    puts
    puts "top_compound_target_clients:"
    TargetClient.where("name LIKE '%,%'").order(:name).limit(15).pluck(:name).each { |name| puts "  #{name}" }
  end

  desc "Merge tag alias duplicates. DRY_RUN=false to write."
  task normalize_tags: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    counts = TagNormalizationService.merge_duplicate_tags!(dry_run: dry_run)
    puts "normalize_tags complete mode=#{dry_run ? 'dry-run' : 'write'} counts=#{counts.inspect}"
  end

  desc "Seed canonical target clients from MethodologyHelper. DRY_RUN=false to write."
  task seed_target_clients: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"

    MethodologyHelper::TARGET_CLIENTS.each do |row|
      existing = TargetClient.find_by(name: row[:name])
      if existing
        puts "exists #{row[:name]}"
        next
      end

      if dry_run
        puts "DRY RUN create #{row[:name]}"
      else
        TargetClient.create!(name: row[:name], description: row[:definition])
        puts "created #{row[:name]}"
      end
    end

    puts "seed_target_clients complete mode=#{dry_run ? 'dry-run' : 'write'}"
  end

  desc "Rename Individual Consumers -> Consumers and backfill M2M target clients. DRY_RUN=false to write."
  task normalize_target_clients: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    renamed = 0
    backfilled = 0

    consumers = TargetClient.find_by(name: "Consumers")
    legacy = TargetClient.find_by(name: "Individual Consumers")
    if legacy && !consumers && !dry_run
      legacy.update!(name: "Consumers", description: MethodologyHelper::TARGET_CLIENTS.find { |row| row[:name] == "Consumers" }&.dig(:definition))
      consumers = legacy
      renamed += 1
    elsif legacy && consumers && !dry_run
      Company.where(target_client_id: legacy.id).update_all(target_client_id: consumers.id, updated_at: Time.current)
      renamed += 1
    end

    Company.includes(:target_client).find_each do |company|
      names = TaxonomyNormalizationService.canonical_target_client_names(company.target_client&.name)
      next if names.empty?

      records = names.filter_map { |name| TargetClient.find_by(name: name) }
      next if records.empty?

      if company.target_client_id != records.first.id
        unless dry_run
          company.target_client_id = records.first.id
          company.save!(validate: false)
        end
        backfilled += 1
      end

      records.each do |target_client|
        next if CompanyTargetClient.exists?(company_id: company.id, target_client_id: target_client.id)

        CompanyTargetClient.create!(company_id: company.id, target_client_id: target_client.id) unless dry_run
        backfilled += 1
      end
    end

    puts "normalize_target_clients complete mode=#{dry_run ? 'dry-run' : 'write'} renamed=#{renamed} backfilled=#{backfilled}"
  end

  desc "Resolve Unknown primary categories via rules/LLM. DRY_RUN=false to write. LIMIT=N optional."
  task resolve_unknown_categories: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    limit = ENV["LIMIT"]&.to_i
    scope = Company.unknown_category.includes(:category, :target_client).order(:id)
    scope = scope.limit(limit) if limit.present?

    counts = Hash.new(0)
    scope.find_each do |company|
      result = CompanyUnknownCategoryResolverService.call(company: company, dry_run: dry_run, min_confidence: ENV.fetch("MIN_CONFIDENCE", CompanyUnknownCategoryResolverService::HIGH_CONFIDENCE.to_s).to_f)
      counts[result["action"]] += 1
      next unless result["action"].in?(%w[would_resolve resolved])

      puts [
        result["action"],
        "company_id=#{company.id}",
        result["company_name"],
        "->",
        result["to_category"],
        "confidence=#{result['confidence']}"
      ].join(" ")
    end

    puts "resolve_unknown_categories complete mode=#{dry_run ? 'dry-run' : 'write'} counts=#{counts.inspect}"
  end

  desc "Seed planned v2 primary categories. DRY_RUN=false to write."
  task seed_categories: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    config = CategoryMigrationService.crosswalk_config

    Array(config["new_categories"]).each do |row|
      existing = Category.find_by(name: row["name"])
      if existing
        puts "exists #{row['name']}"
        next
      end

      if dry_run
        puts "DRY RUN create #{row['name']}"
      else
        Category.create!(name: row["name"], description: row["description"])
        puts "created #{row['name']}"
      end
    end

    puts "seed_categories complete mode=#{dry_run ? 'dry-run' : 'write'}"
  end

  desc "Dry-run category migration crosswalk v2. LIMIT=N optional."
  task dry_run_category_migration: :environment do
    limit = ENV["LIMIT"]&.to_i
    scope = Company.publicly_visible.includes(:category, :tags).order(:id)
    scope = scope.limit(limit) if limit.present?

    counts = Hash.new(0)
    scope.find_each do |company|
      result = CategoryMigrationService.call(company: company, dry_run: true)
      counts[result["action"]] += 1
      next unless result["action"] == "would_migrate"

      puts [
        result["action"],
        "company_id=#{company.id}",
        result["company_name"],
        "#{result['from_category']} -> #{result['to_category']}"
      ].join(" ")
    end

    puts "dry_run_category_migration complete counts=#{counts.inspect}"
  end

  desc "Apply category migration crosswalk v2. DRY_RUN=false to write. LIMIT=N optional."
  task apply_category_migration: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    limit = ENV["LIMIT"]&.to_i
    scope = Company.publicly_visible.includes(:category, :tags).order(:id)
    scope = scope.limit(limit) if limit.present?

    counts = Hash.new(0)
    scope.find_each do |company|
      result = CategoryMigrationService.call(company: company, dry_run: dry_run)
      counts[result["action"]] += 1
      next unless result["action"].in?(%w[would_migrate migrated])

      puts [
        result["action"],
        "company_id=#{company.id}",
        result["company_name"],
        "#{result['from_category']} -> #{result['to_category']}"
      ].join(" ")
    end

    puts "apply_category_migration complete mode=#{dry_run ? 'dry-run' : 'write'} counts=#{counts.inspect}"
  end

  desc "Export remaining Unknown categories to CSV for human review."
  task export_unknown_categories: :environment do
    path = Rails.root.join("tmp", "unknown_categories_#{Time.current.strftime('%Y%m%d')}.csv")
    CSV.open(path, "w") do |csv|
      csv << %w[company_id name main_url description target_client suggested_category confidence mode action tags]
      Company.unknown_category.includes(:category, :target_client, :tags).order(:id).find_each do |company|
        result = CompanyUnknownCategoryResolverService.call(company: company, dry_run: true, min_confidence: 0.0)
        csv << [
          company.id,
          company.name,
          company.main_url,
          company.description.to_s.truncate(500),
          company.target_client&.name,
          result["suggested_category"] || result["to_category"],
          result["confidence"],
          result["mode"],
          result["action"],
          company.tags.map(&:name).join("; ")
        ]
      end
    end

    puts "export_unknown_categories complete path=#{path} rows=#{Company.unknown_category.count}"
  end

  desc "Remove unused non-canonical BusinessModel records. DRY_RUN=false to write."
  task retire_legacy_business_models: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    canonical = MethodologyHelper::REVENUE_MODEL_NAMES + ["Unknown"]
    removed = 0

    BusinessModel.where.not(name: canonical).find_each do |model|
      next if CompanyBusinessModel.exists?(business_model_id: model.id) || Company.exists?(business_model_id: model.id)

      if dry_run
        puts "DRY RUN delete #{model.name} id=#{model.id}"
      else
        model.destroy!
        puts "deleted #{model.name}"
      end
      removed += 1
    end

    puts "retire_legacy_business_models complete mode=#{dry_run ? 'dry-run' : 'write'} removed=#{removed}"
  end

  desc "Sync legacy business_model_id from M2M revenue models. DRY_RUN=false to write."
  task sync_legacy_revenue_fk: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    changed = 0

    Company.includes(:company_business_models).find_each do |company|
      next if company.company_business_models.empty?

      target_id = company.company_business_models.order(:id).pick(:business_model_id)
      next if target_id.blank? || company.business_model_id == target_id

      changed += 1
      company.update_columns(business_model_id: target_id, updated_at: Time.current) unless dry_run
    end

    puts "sync_legacy_revenue_fk complete mode=#{dry_run ? 'dry-run' : 'write'} changed=#{changed}"
  end

  desc "Run full taxonomy migration pipeline in order. DRY_RUN=false to write."
  task migrate_all: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    puts "taxonomy:migrate_all starting mode=#{dry_run ? 'dry-run' : 'write'}"

    steps = %w[
      seed_revenue_models
      seed_target_clients
      seed_categories
      normalize_tags
      normalize_revenue_models
      backfill_revenue_models
      normalize_target_clients
      resolve_unknown_categories
      apply_category_migration
    ]

    steps.each do |step|
      puts
      puts "=== taxonomy:#{step} ==="
      Rake::Task["taxonomy:#{step}"].reenable
      Rake::Task["taxonomy:#{step}"].invoke
    end

    puts
    puts "taxonomy:migrate_all complete"
    Rake::Task["taxonomy:audit"].reenable
    Rake::Task["taxonomy:audit"].invoke
  end
end
