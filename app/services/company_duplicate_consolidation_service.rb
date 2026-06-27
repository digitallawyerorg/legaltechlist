class CompanyDuplicateConsolidationService
  RUN_TYPE = "duplicate_domain_consolidation".freeze
  AGENT_NAME = "DuplicateConsolidationAgent".freeze
  MERGE_FIELDS = %w[
    main_url
    location
    founded_date
    description
    category_id
    sub_category_id
    business_model_id
    target_client_id
    crunchbase_url
    linkedin_url
    facebook_url
    total_funding_amount_usd
    funding_status
    number_of_funding_rounds
    employee_count
    founders
    source
    source_url
  ].freeze

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(domains: nil, reviewer: nil, notes: nil, dry_run: false)
    @domains = Array(domains).compact_blank.map { |domain| domain.to_s.downcase.sub(/\Awww\./, "") }
    @reviewer = reviewer
    @notes = notes
    @dry_run = dry_run
  end

  def call
    run = PipelineRun.create!(
      name: "Duplicate-domain consolidation",
      run_type: RUN_TYPE,
      status: "pending",
      agent_name: AGENT_NAME
    )

    run.mark_running!
    results = duplicate_groups.map { |domain, companies| consolidate_group(domain, companies) }
    run.mark_succeeded!(records_processed: results.sum { |result| result["company_ids"].size }, details: details_payload(results))
    run
  rescue StandardError => e
    run&.mark_failed!(e.message, details: failure_payload(e))
    raise
  end

  private

  attr_reader :domains, :reviewer, :notes, :dry_run

  def duplicate_groups
    groups = Company.where.not(main_url: [nil, ""]).select(:id, :main_url, :canonical_domain).group_by do |company|
      company.canonical_domain.presence || company.canonical_main_domain
    end

    groups = groups.slice(*domains) if domains.any?
    groups.transform_values { |records| Company.includes(:category, :business_model, :target_client).where(id: records.map(&:id)).to_a }
      .select { |_domain, records| records.count(&:visible?) > 1 }
  end

  def consolidate_group(domain, companies)
    keeper = companies.max_by { |company| [keeper_score(company), -company.id] }
    duplicates = companies.reject { |company| company.id == keeper.id }
    merged_fields = duplicates.each_with_object({}) { |duplicate, fields| fields[duplicate.id] = merge_fields(keeper, duplicate) }

    unless dry_run
      Company.transaction do
        save_keeper!(keeper)
        duplicates.each { |duplicate| hide_duplicate!(duplicate, keeper) }
      end
    end

    {
      "domain" => domain,
      "keeper_id" => keeper.id,
      "keeper_name" => keeper.name,
      "company_ids" => companies.map(&:id),
      "hidden_company_ids" => duplicates.map(&:id),
      "merged_fields" => merged_fields,
      "dry_run" => dry_run
    }
  end

  def merge_fields(keeper, duplicate)
    updates = MERGE_FIELDS.each_with_object({}) do |field, attrs|
      next unless keeper.respond_to?(field) && duplicate.respond_to?(field)
      next if duplicate.public_send(field).blank?
      next unless merge_field_blank?(keeper, field)

      attrs[field] = duplicate.public_send(field)
    end

    keeper.assign_attributes(updates)
    updates.keys
  end

  def merge_field_blank?(keeper, field)
    value = keeper.public_send(field)
    return true if value.blank?
    return unknown_taxonomy?(field, value) if field.in?(%w[category_id sub_category_id business_model_id target_client_id])

    false
  end

  def unknown_taxonomy?(field, value)
    association = field.delete_suffix("_id")
    keeper_record = keeper_association(association, value)
    keeper_record&.name.to_s.casecmp?("unknown")
  end

  def keeper_association(association, value)
    model = association.camelize.constantize
    model.find_by(id: value)
  rescue NameError
    nil
  end

  def save_keeper!(keeper)
    keeper.canonical_domain = keeper.canonical_main_domain if keeper.respond_to?(:canonical_domain)
    keeper.fingerprint = keeper.calculated_fingerprint if keeper.respond_to?(:fingerprint)
    keeper.quality_status = "source_verified" if keeper.quality_status.blank? || keeper.quality_status == "needs_review"
    keeper.verification_verdict = "duplicate_consolidation_keeper"
    keeper.quality_reviewed_at = Time.current
    keeper.enriched_at ||= Time.current if keeper.respond_to?(:enriched_at)
    keeper.skip_geocoding = true
    keeper.save!(validate: false)
  end

  def hide_duplicate!(duplicate, keeper)
    duplicate.visible = false
    duplicate.quality_status = "duplicate_hidden"
    duplicate.verification_verdict = "duplicate_consolidated_into_#{keeper.id}"
    duplicate.quality_reviewed_at = Time.current
    duplicate.human_reviewed_at = Time.current
    duplicate.skip_geocoding = true
    duplicate.save!(validate: false)
  end

  def keeper_score(company)
    [
      company.visible? ? 1_000 : 0,
      quality_status_score(company),
      taxonomy_score(company),
      source_score(company),
      description_score(company),
      company.location.present? ? 10 : 0,
      company.founded_date.present? ? 10 : 0
    ].sum
  end

  def quality_status_score(company)
    case company.quality_status
    when "verified", "source_verified" then 150
    when "needs_review" then -50
    when "duplicate_hidden", "rejected" then -200
    else 0
    end
  end

  def taxonomy_score(company)
    [company.category, company.business_model, company.target_client].sum do |record|
      record.present? && !record.name.to_s.casecmp?("unknown") ? 60 : 0
    end
  end

  def source_score(company)
    %w[crunchbase_url linkedin_url source_url].sum { |field| company.public_send(field).present? ? 20 : 0 }
  end

  def description_score(company)
    length = company.description.to_s.squish.length
    return 80 if length >= 80
    return 40 if length >= 40

    0
  end

  def details_payload(results)
    {
      "reviewer" => reviewer,
      "notes" => notes,
      "dry_run" => dry_run,
      "domains" => domains,
      "results" => results,
      "created_at" => Time.current.utc.iso8601,
      "completed_at" => Time.current.utc.iso8601
    }
  end

  def failure_payload(error)
    {
      "reviewer" => reviewer,
      "notes" => notes,
      "dry_run" => dry_run,
      "domains" => domains,
      "error_class" => error.class.name,
      "failed_at" => Time.current.utc.iso8601
    }
  end
end
