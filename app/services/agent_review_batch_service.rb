class AgentReviewBatchService
  RUN_TYPE = "agent_review_batch".freeze
  AGENT_NAME = "AgentReviewBatchService".freeze
  REVIEW_TYPES = %w[description duplicate_domain].freeze
  DEFAULT_LIMIT = 5
  DEFAULT_MAX_LIMIT = 25
  DEFAULT_MAX_COST_USD = 5.0
  TRACKED_COMPANY_FIELDS = %w[
    name description main_url visible quality_status verification_verdict quality_score canonical_domain fingerprint updated_at
  ].freeze

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(review_type:, limit: DEFAULT_LIMIT, dry_run: true, reviewer: nil, notes: nil, max_limit: DEFAULT_MAX_LIMIT, max_cost_usd: DEFAULT_MAX_COST_USD, stop_on_error: true)
    @review_type = review_type.to_s
    @limit = limit.to_i
    @dry_run = ActiveModel::Type::Boolean.new.cast(dry_run)
    @reviewer = reviewer
    @notes = notes
    @max_limit = max_limit.to_i
    @max_cost_usd = max_cost_usd.to_f
    @stop_on_error = ActiveModel::Type::Boolean.new.cast(stop_on_error)
  end

  def call
    validate_options!
    run = PipelineRun.create!(
      name: "Agent review batch: #{review_type}",
      run_type: RUN_TYPE,
      status: "pending",
      agent_name: AGENT_NAME
    )

    run.mark_running!
    run.mark_succeeded!(records_processed: records_processed, details: details_payload)
    run
  rescue StandardError => e
    run&.mark_failed!(e.message, details: failure_payload(e))
    raise
  end

  private

  attr_reader :review_type, :limit, :dry_run, :reviewer, :notes, :max_limit, :max_cost_usd, :stop_on_error

  def validate_options!
    raise ArgumentError, "review_type must be one of: #{REVIEW_TYPES.to_sentence}" unless REVIEW_TYPES.include?(review_type)
    raise ArgumentError, "limit must be greater than 0" unless limit.positive?
    raise ArgumentError, "limit #{limit} exceeds max_limit #{max_limit}" if limit > max_limit
    raise ArgumentError, "max_cost_usd must be greater than or equal to 0" if max_cost_usd.negative?
  end

  def details_payload
    return @details_payload if defined?(@details_payload)

    started_at = Time.current.utc.iso8601
    companies = candidate_companies
    child_runs = dry_run ? [] : execute_child_runs(companies)

    @details_payload = {
      "reviewer" => reviewer,
      "notes" => notes,
      "mode" => "batch_no_public_writes",
      "review_type" => review_type,
      "dry_run" => dry_run,
      "limit" => limit,
      "max_limit" => max_limit,
      "max_cost_usd" => max_cost_usd,
      "stop_on_error" => stop_on_error,
      "candidate_company_ids" => companies.map(&:id),
      "child_review_run_ids" => child_runs.map { |child| child.fetch("run_id") },
      "results" => child_runs,
      "summary" => summary(child_runs),
      "created_at" => started_at,
      "completed_at" => Time.current.utc.iso8601
    }
  end

  def failure_payload(error)
    {
      "reviewer" => reviewer,
      "notes" => notes,
      "mode" => "batch_no_public_writes",
      "review_type" => review_type,
      "dry_run" => dry_run,
      "limit" => limit,
      "max_limit" => max_limit,
      "max_cost_usd" => max_cost_usd,
      "stop_on_error" => stop_on_error,
      "error_class" => error.class.name,
      "failed_at" => Time.current.utc.iso8601
    }
  end

  def records_processed
    dry_run ? 0 : details_payload.fetch("child_review_run_ids").size
  end

  def execute_child_runs(companies)
    results = []

    companies.each do |company|
      result = execute_one(company)
      results << result
      raise CostLimitExceededError, "Batch estimated cost #{total_estimated_cost(results)} exceeds max_cost_usd #{max_cost_usd}" if total_estimated_cost(results) > max_cost_usd
    rescue StandardError => e
      raise if stop_on_error

      results << {
        "company_id" => company.id,
        "company_name" => company.name,
        "status" => "failed",
        "error_class" => e.class.name,
        "error_message" => e.message
      }
    end

    results
  end

  def execute_one(company)
    tracked_records = tracked_records_for(company)
    before_attributes = tracked_records.to_h { |record| [record.id, tracked_attributes(record)] }
    child_run = child_service_for(company)
    tracked_records.each(&:reload)
    mutation_failures = tracked_records.filter_map do |record|
      next if tracked_attributes(record) == before_attributes.fetch(record.id)

      { "company_id" => record.id, "company_name" => record.name }
    end
    raise PublicWriteDetectedError, "Public company fields changed during batch review: #{mutation_failures.to_json}" if mutation_failures.any?

    {
      "run_id" => child_run.id,
      "company_id" => company.id,
      "company_name" => company.name,
      "status" => child_run.status,
      "estimated_cost_usd" => estimated_cost(child_run.details),
      "updated_at_unchanged" => true
    }
  end

  def child_service_for(company)
    case review_type
    when "description"
      CompanyAgentReviewService.call(company: company, reviewer: reviewer, notes: "Batch description review")
    when "duplicate_domain"
      DuplicateDomainReviewService.call(company: company, reviewer: reviewer, notes: "Batch duplicate-domain review")
    end
  end

  def candidate_companies
    return @candidate_companies if defined?(@candidate_companies)

    scope = case review_type
    when "description"
      Company.description_review_candidates.order(updated_at: :asc)
    when "duplicate_domain"
      Company.duplicate_domain_candidates.order(updated_at: :asc)
    end

    @candidate_companies = scope.limit(limit).to_a
  end

  def tracked_records_for(company)
    records = [company]
    records += duplicate_candidates_for(company) if review_type == "duplicate_domain"
    records.uniq(&:id)
  end

  def duplicate_candidates_for(company)
    domain = company.canonical_domain.presence || company.canonical_main_domain
    return [] if domain.blank?

    Company.where.not(id: company.id).where.not(main_url: [nil, ""]).select { |candidate| (candidate.canonical_domain.presence || candidate.canonical_main_domain) == domain }.first(10)
  end

  def tracked_attributes(company)
    company.attributes.slice(*TRACKED_COMPANY_FIELDS)
  end

  def summary(results)
    {
      "requested_count" => candidate_companies.size,
      "executed_count" => results.count { |result| result["status"] == "succeeded" },
      "failed_count" => results.count { |result| result["status"] == "failed" },
      "total_estimated_cost_usd" => total_estimated_cost(results),
      "dry_run_message" => dry_run ? "Dry run only; no child review runs were created." : nil
    }.compact
  end

  def total_estimated_cost(results)
    results.sum { |result| result["estimated_cost_usd"].to_f }.round(8)
  end

  def estimated_cost(details)
    cost_values(details).sum.round(8)
  end

  def cost_values(value)
    case value
    when Hash
      value.flat_map do |key, nested_value|
        key.to_s == "estimated_cost_usd" ? nested_value.to_f : cost_values(nested_value)
      end
    when Array
      value.flat_map { |nested_value| cost_values(nested_value) }
    else
      []
    end
  end

  class PublicWriteDetectedError < StandardError; end
  class CostLimitExceededError < StandardError; end
end
