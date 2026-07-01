# frozen_string_literal: true

namespace :slugs do
  SLUG_MODELS = {
    "Company" => :name,
    "Category" => :name,
    "BusinessModel" => :name,
    "TargetClient" => :name,
    "Tag" => :name
  }.freeze

  desc "Report slug collisions and missing slugs. Optional MODEL=Company"
  task audit: :environment do
    models = SLUG_MODELS.slice(*(ENV["MODEL"].present? ? [ENV["MODEL"]] : SLUG_MODELS.keys))

    models.each do |model_name, source_attr|
      model = model_name.constantize
      puts "=== #{model_name} ==="
      total = model.count
      with_slug = model.where.not(slug: [nil, ""]).count
      puts "total=#{total} with_slug=#{with_slug} missing=#{total - with_slug}"

      by_slug = Hash.new { |hash, key| hash[key] = [] }
      model.pluck(:id, source_attr, :slug).each do |id, name, slug|
        key = slug.presence || model.slug_for_name(name)
        by_slug[key] << { id: id, name: name, slug: slug }
      end

      collisions = by_slug.select { |_slug, rows| rows.size > 1 }
      puts "collision_groups=#{collisions.size} records_in_collisions=#{collisions.values.flatten.size}"
      collisions.sort_by { |slug, _| slug }.each do |slug, rows|
        puts "  #{slug}: #{rows.map { |row| "##{row[:id]} #{row[:name].inspect}" }.join(', ')}"
      end
      puts
    end
  end

  desc "Backfill slugs for all URL models. DRY_RUN=false to write."
  task backfill: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    models = SLUG_MODELS.slice(*(ENV["MODEL"].present? ? [ENV["MODEL"]] : SLUG_MODELS.keys))

    models.each do |model_name, source_attr|
      model = model_name.constantize
      updates = model.assign_unique_slugs!(scope: model.where(slug: [nil, ""]), slug_source: source_attr, dry_run: dry_run)
      puts "#{model_name}: #{updates.size} slugs #{dry_run ? 'would be' : 'were'} assigned"
    end

    puts "slugs:backfill complete mode=#{dry_run ? 'dry-run' : 'write'}"
  end

  desc "Merge duplicate companies that share the same fingerprint. DRY_RUN=false to write."
  task merge_fingerprint_duplicates: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    merged_groups = 0
    deleted_records = 0

    fingerprint_groups = Company.where.not(fingerprint: [nil, ""]).group(:fingerprint).having("COUNT(*) > 1").pluck(:fingerprint)
    fingerprint_groups.each do |fingerprint|
      companies = Company.includes(:category, :secondary_category, :business_model, :target_client, :successor_company, :taggings, :tags)
                         .where(fingerprint: fingerprint)
                         .order(:id)
                         .to_a
      next if companies.size < 2

      service = CompanyDuplicateConsolidationService.allocate
      skip_reason = service.send(:consolidation_skip_reason, companies)
      if skip_reason
        puts "skip fingerprint=#{fingerprint} reason=#{skip_reason} ids=#{companies.map(&:id).join(',')}"
        next
      end

      keeper = companies.max_by { |company| [company.visible? ? 1 : 0, company.id] }
      duplicates = companies.reject { |company| company.id == keeper.id }
      line = "fingerprint=#{fingerprint} keeper=##{keeper.id} delete=#{duplicates.map(&:id).join(',')}"

      if dry_run
        puts "DRY RUN #{line}"
      else
        Company.transaction do
          duplicates.each { |duplicate| service.send(:delete_duplicate!, duplicate, keeper) }
          service.send(:save_keeper!, keeper)
        end
        puts line
      end

      merged_groups += 1
      deleted_records += duplicates.size
    end

    puts "merge_fingerprint_duplicates complete mode=#{dry_run ? 'dry-run' : 'write'} groups=#{merged_groups} deleted=#{deleted_records}"
  end
end
