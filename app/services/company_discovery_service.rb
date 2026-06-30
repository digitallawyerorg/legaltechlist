class CompanyDiscoveryService
  RUN_TYPE = "company_discovery".freeze
  AGENT_NAME = "CompanyDiscoveryService".freeze
  SOURCE = "llm_discovery".freeze
  PROPOSAL_TYPE = "discovery_candidate".freeze
  DISCOVERY_TYPES = %w[category competitors year country funding_year].freeze
  DEFAULT_LIMIT = 25
  FUNDING_YEAR_DEFAULT_LIMIT = 10
  DEFAULT_MAX_LIMIT = 50
  DEFAULT_MAX_COST_USD = 5.0
  ESTIMATED_COST_PER_SEARCH_USD = 0.15

  class CostLimitExceededError < StandardError; end

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def self.enqueue(**kwargs)
    service = new(**kwargs)
    service.validate_options!
    run = PipelineRun.create!(
      name: service.send(:pipeline_run_name),
      run_type: RUN_TYPE,
      status: "pending",
      agent_name: AGENT_NAME
    )
    CompanyDiscoveryJob.perform_later(run.id, service.job_arguments)
    run
  end

  def self.perform_run!(run_id, arguments = {})
    args = arguments.stringify_keys
    admin_user_id = args.delete("admin_user_id")
    service = new(**args.symbolize_keys.merge(admin_user: AdminUser.find_by(id: admin_user_id)))
    service.perform!(PipelineRun.find(run_id))
  end

  def initialize(discovery_type:, limit: nil, dry_run: true, queue_proposals: false, reviewer: nil, notes: nil, max_limit: DEFAULT_MAX_LIMIT, max_cost_usd: DEFAULT_MAX_COST_USD, category: nil, company_id: nil, company_name: nil, year: nil, country: nil, funding_year: nil, search_service: CompanyDiscoverySearchService, admin_user: nil)
    @discovery_type = discovery_type.to_s
    @limit = (limit || default_limit_for(@discovery_type)).to_i
    @dry_run = ActiveModel::Type::Boolean.new.cast(dry_run)
    @queue_proposals = ActiveModel::Type::Boolean.new.cast(queue_proposals)
    @reviewer = reviewer
    @notes = notes
    @max_limit = max_limit.to_i
    @max_cost_usd = max_cost_usd.to_f
    @category = category
    @company_id = company_id
    @company_name = company_name
    @year = year
    @country = country
    @funding_year = funding_year
    @search_service = search_service
    @admin_user = admin_user
  end

  def call
    validate_options!
    run = PipelineRun.create!(
      name: pipeline_run_name,
      run_type: RUN_TYPE,
      status: "pending",
      agent_name: AGENT_NAME
    )
    perform!(run)
  end

  def perform!(run)
    run.mark_running!
    details = build_details(run)
    run.mark_succeeded!(records_processed: records_processed(details), details: details)
    run
  rescue StandardError => e
    run.mark_failed!(e.message, details: failure_payload(e))
    raise
  end

  def job_arguments
    {
      "discovery_type" => discovery_type,
      "limit" => limit,
      "dry_run" => dry_run,
      "queue_proposals" => queue_proposals,
      "reviewer" => reviewer,
      "notes" => notes,
      "max_limit" => max_limit,
      "max_cost_usd" => max_cost_usd,
      "category" => category,
      "company_id" => company_id,
      "company_name" => company_name,
      "year" => year,
      "country" => country,
      "funding_year" => funding_year,
      "admin_user_id" => admin_user&.id
    }
  end

  private

  attr_reader :discovery_type, :limit, :dry_run, :queue_proposals, :reviewer, :notes, :max_limit, :max_cost_usd, :category, :company_id, :company_name, :year, :country, :funding_year, :search_service, :admin_user

  def build_details(run)
    started_at = Time.current.utc.iso8601
    search_payload = search_service.call(
      discovery_type: discovery_type,
      context: discovery_context,
      exclusion_list: exclusion_list,
      limit: limit
    )
    enforce_cost_cap!(search_payload)
    normalized_candidates = normalize_candidates(search_payload)
    proposal_results = queue_proposals ? queue_candidate_proposals(normalized_candidates, run.id) : []

    {
      "reviewer" => reviewer,
      "notes" => notes,
      "mode" => dry_run ? "discovery_dry_run_no_proposals" : (queue_proposals ? "discovery_with_proposal_queue" : "discovery_search_only"),
      "source" => SOURCE,
      "discovery_type" => discovery_type,
      "discovery_context" => discovery_context,
      "dry_run" => dry_run,
      "queue_proposals" => queue_proposals,
      "limit" => limit,
      "max_limit" => max_limit,
      "max_cost_usd" => max_cost_usd,
      "estimated_cost_usd" => estimated_search_cost(search_payload),
      "exclusion_context" => exclusion_context,
      "search" => search_payload,
      "candidates" => normalized_candidates,
      "proposal_results" => proposal_results,
      "summary" => summary(normalized_candidates, proposal_results, search_payload),
      "created_at" => started_at,
      "completed_at" => Time.current.utc.iso8601
    }
  end

  def records_processed(details)
    return 0 if dry_run || !queue_proposals

    Array(details["proposal_results"]).size
  end

  def validate_options!
    raise ArgumentError, "discovery_type must be one of: #{DISCOVERY_TYPES.to_sentence}" unless DISCOVERY_TYPES.include?(discovery_type)
    raise ArgumentError, "limit must be greater than 0" unless limit.positive?
    raise ArgumentError, "limit #{limit} exceeds max_limit #{max_limit}" if limit > max_limit
    raise ArgumentError, "max_cost_usd must be greater than or equal to 0" if max_cost_usd.negative?
    raise ArgumentError, "CATEGORY is required for category discovery" if discovery_type == "category" && category.blank?
    raise ArgumentError, "COMPANY_ID or COMPANY_NAME is required for competitors discovery" if discovery_type == "competitors" && company_id.blank? && company_name.blank?
    raise ArgumentError, "YEAR is required for year discovery" if discovery_type == "year" && year.blank?
    raise ArgumentError, "COUNTRY is required for country discovery" if discovery_type == "country" && country.blank?
    raise ArgumentError, "FUNDING_YEAR is required for funding_year discovery" if discovery_type == "funding_year" && funding_year.blank?
    raise ArgumentError, "queue_proposals requires dry_run=false" if queue_proposals && dry_run
  end

  def pipeline_run_name
    case discovery_type
    when "category"
      "Company discovery: #{category}"
    when "competitors"
      "Company discovery: competitors for #{discovery_context[:company_name]}"
    when "year"
      "Company discovery: founded in #{year}"
    when "country"
      "Company discovery: #{country}"
    when "funding_year"
      "Company discovery: funding in #{funding_year}"
    else
      "Company discovery: #{discovery_type}"
    end
  end

  def discovery_context
    @discovery_context ||= case discovery_type
    when "category"
      { category: category }
    when "competitors"
      company = company_id.present? ? Company.find(company_id) : nil
      {
        company_id: company&.id,
        company_name: company&.name || company_name,
        company_website: company&.main_url,
        company_category: company&.category&.name
      }
    when "year"
      { year: year }
    when "country"
      { country: country }
    when "funding_year"
      { funding_year: funding_year }
    else
      {}
    end
  end

  def failure_payload(error)
    {
      "reviewer" => reviewer,
      "notes" => notes,
      "mode" => dry_run ? "discovery_dry_run_no_proposals" : (queue_proposals ? "discovery_with_proposal_queue" : "discovery_search_only"),
      "source" => SOURCE,
      "discovery_type" => discovery_type,
      "discovery_context" => discovery_context,
      "dry_run" => dry_run,
      "queue_proposals" => queue_proposals,
      "limit" => limit,
      "max_limit" => max_limit,
      "max_cost_usd" => max_cost_usd,
      "error_class" => error.class.name,
      "failed_at" => Time.current.utc.iso8601
    }
  end

  def normalize_candidates(search_payload)
    Array(search_payload["companies"]).map { |company| DiscoveryCandidateNormalizerService.call(company) }
  end

  def queue_candidate_proposals(candidates, pipeline_run_id)
    raise ArgumentError, "queue_proposals requires dry_run=false" if dry_run

    user = admin_user || AdminUser.first
    raise ArgumentError, "No admin user available for proposal queueing" unless user

    candidates.each_with_index.filter_map do |candidate, index|
      next unless candidate["status"] == "absent_candidate"

      candidate_with_run = candidate.merge("pipeline_run_id" => pipeline_run_id)
      CompanyCandidateRowProcessorService.call(
        candidate: candidate_with_run,
        index: index,
        admin_user: user,
        pipeline_run_id: pipeline_run_id,
        source: SOURCE,
        proposal_type: PROPOSAL_TYPE,
        source_label: "LLM Discovery",
        skip_auto_draft: true
      )
    end
  end

  def exclusion_list
    rows = Company.where(visible: true).where.not(name: [nil, ""]).pluck(:name, :main_url)
    {
      "names" => rows.map(&:first).compact_blank.uniq,
      "domains" => rows.filter_map { |_name, main_url| Company.canonical_domain_for(main_url) }.uniq
    }
  end

  def exclusion_context
    {
      "visible_company_count" => Company.where(visible: true).count,
      "excluded_name_count" => exclusion_list["names"].size,
      "excluded_domain_count" => exclusion_list["domains"].size
    }
  end

  def summary(candidates, proposal_results, search_payload)
    discovered_count = Array(search_payload["companies"]).size
    duplicate_count = candidates.count { |candidate| candidate["status"] == "existing_or_possible_duplicate" }
    ops_note = ops_visibility_note(discovered_count, duplicate_count, candidates, search_payload)

    {
      "requested_limit" => limit,
      "discovered_count" => discovered_count,
      "normalized_count" => candidates.size,
      "absent_candidates" => candidates.count { |candidate| candidate["status"] == "absent_candidate" },
      "existing_or_possible_duplicates" => duplicate_count,
      "rejected_nonprofit_advocacy" => candidates.count { |candidate| candidate["status"] == "rejected_nonprofit_advocacy" },
      "verified_websites" => candidates.count { |candidate| candidate["website_verified"] },
      "queued_proposals" => proposal_results.size,
      "search_mode" => search_payload["mode"],
      "empty_result_retry" => search_payload["empty_result_retry"],
      "ops_note" => ops_note,
      "dry_run_message" => dry_run ? "Dry run only; no proposals were created." : nil,
      "queue_proposals_message" => !dry_run && !queue_proposals ? "Search completed; set QUEUE_PROPOSALS=true to create proposals." : nil,
      "search_error" => search_payload["error_message"]
    }.compact
  end

  def default_limit_for(type)
    type == "funding_year" ? FUNDING_YEAR_DEFAULT_LIMIT : DEFAULT_LIMIT
  end

  def ops_visibility_note(discovered_count, duplicate_count, candidates, search_payload)
    if search_payload["error_message"].present?
      "Search error: #{search_payload['error_message']}"
    elsif discovered_count.zero?
      retry_note = search_payload["empty_result_retry"] ? " (retried once)" : ""
      "Zero companies returned from search#{retry_note}."
    elsif duplicate_count.positive? && candidates.count { |candidate| candidate["status"] == "absent_candidate" }.zero?
      "All #{discovered_count} discovered companies were duplicates or filtered."
    end
  end

  def enforce_cost_cap!(search_payload)
    estimated = estimated_search_cost(search_payload)
    return if estimated <= max_cost_usd

    raise CostLimitExceededError, "Estimated discovery cost $#{estimated.round(2)} exceeds max_cost_usd $#{max_cost_usd.round(2)}"
  end

  def estimated_search_cost(search_payload)
    return 0.0 if search_payload["mode"] == "disabled_no_responses_web_search"

    ESTIMATED_COST_PER_SEARCH_USD
  end
end
