namespace :agent_reviews do
  desc "Create one manual company review PipelineRun without changing public company data. Optional: COMPANY_ID, QUEUE, REVIEWER, NOTES."
  task manual_company_review: :environment do
    company = if ENV["COMPANY_ID"].present?
      Company.find(ENV["COMPANY_ID"])
    else
      scope = case ENV.fetch("QUEUE", "weak_description")
      when "missing_url" then Company.missing_main_url
      when "duplicate_domain" then Company.duplicate_domain_candidates
      when "duplicate_name" then Company.duplicate_name_candidates
      when "needs_review" then Company.needs_review
      when "all" then Company.all
      else Company.weak_description
      end

      scope.order(:id).first || Company.order(:id).first
    end

    abort "No company found for manual review." unless company

    run = ManualCompanyReviewService.call(
      company: company,
      reviewer: ENV["REVIEWER"],
      notes: ENV["NOTES"]
    )

    puts "Created manual company review run_id=#{run.id} company_id=#{company.id} company_name=#{company.name.inspect} status=#{run.status}"
    puts "Mode: no public company fields were changed."
  end

  desc "Run proposal-only evidence and verifier agents for one company. Optional: COMPANY_ID, QUEUE, REVIEWER, NOTES."
  task company_agent_review: :environment do
    company = if ENV["COMPANY_ID"].present?
      Company.find(ENV["COMPANY_ID"])
    else
      company_for_queue(ENV.fetch("QUEUE", "weak_description"))
    end

    abort "No company found for agent review." unless company

    run = CompanyAgentReviewService.call(
      company: company,
      reviewer: ENV["REVIEWER"],
      notes: ENV["NOTES"]
    )

    puts "Created company agent review run_id=#{run.id} company_id=#{company.id} company_name=#{company.name.inspect} status=#{run.status}"
    puts "Verdict: #{run.details.dig('verification', 'verdict')}"
    puts "Mode: proposal-only; no public company fields were changed."
  end

  desc "Run guarded proposal-only agent review batch. Defaults to DRY_RUN=true. Optional: REVIEW_TYPE=description|duplicate_domain, LIMIT, MAX_LIMIT, MAX_COST_USD, REVIEWER, NOTES, STOP_ON_ERROR."
  task batch: :environment do
    dry_run = ENV.fetch("DRY_RUN", ENV["RUN"] == "true" ? "false" : "true")
    review_type = ENV.fetch("REVIEW_TYPE", "description")
    limit = ENV.fetch("LIMIT", AgentReviewBatchService::DEFAULT_LIMIT)
    max_limit = ENV.fetch("MAX_LIMIT", AgentReviewBatchService::DEFAULT_MAX_LIMIT)
    max_cost_usd = ENV.fetch("MAX_COST_USD", AgentReviewBatchService::DEFAULT_MAX_COST_USD)
    stop_on_error = ENV.fetch("STOP_ON_ERROR", "true")

    run = AgentReviewBatchService.call(
      review_type: review_type,
      limit: limit,
      dry_run: dry_run,
      reviewer: ENV["REVIEWER"],
      notes: ENV["NOTES"],
      max_limit: max_limit,
      max_cost_usd: max_cost_usd,
      stop_on_error: stop_on_error
    )

    puts "Created agent review batch run_id=#{run.id} review_type=#{review_type} status=#{run.status}"
    puts "Dry run: #{run.details['dry_run']}"
    puts "Candidate company ids: #{run.details['candidate_company_ids'].join(', ')}"
    puts "Child review run ids: #{run.details['child_review_run_ids'].join(', ')}"
    puts "Summary: #{run.details['summary'].to_json}"
    puts "Mode: guarded batch; public company fields are checked after each child review."
  end

  def company_for_queue(queue)
    scope = case queue
    when "missing_url" then Company.missing_main_url
    when "duplicate_domain" then Company.duplicate_domain_candidates
    when "duplicate_name" then Company.duplicate_name_candidates
    when "needs_review" then Company.needs_review
    when "all" then Company.all
    else Company.weak_description
    end

    scope.order(:id).first || Company.order(:id).first
  end
end
