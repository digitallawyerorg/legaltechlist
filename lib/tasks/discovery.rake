namespace :discovery do
  # Ops fallback — primary UX is /admin/discoveries/new
  desc "Run LLM web-search company discovery. Defaults to DRY_RUN=true. Optional: DISCOVERY_TYPE=category|competitors|year|country|funding_year, CATEGORY, COMPANY_ID, COMPANY_NAME, LIMIT, MAX_LIMIT, MAX_COST_USD, REVIEWER, NOTES, QUEUE_PROPOSALS."
  task run: :environment do
    dry_run = ENV.fetch("DRY_RUN", ENV["RUN"] == "true" ? "false" : "true")
    discovery_type = ENV.fetch("DISCOVERY_TYPE", "category")
    limit = ENV.fetch("LIMIT", CompanyDiscoveryService::DEFAULT_LIMIT)
    max_limit = ENV.fetch("MAX_LIMIT", CompanyDiscoveryService::DEFAULT_MAX_LIMIT)
    max_cost_usd = ENV.fetch("MAX_COST_USD", CompanyDiscoveryService::DEFAULT_MAX_COST_USD)
    queue_proposals = ENV.fetch("QUEUE_PROPOSALS", "false")

    run = CompanyDiscoveryService.call(
      discovery_type: discovery_type,
      category: ENV["CATEGORY"],
      company_id: ENV["COMPANY_ID"],
      company_name: ENV["COMPANY_NAME"],
      year: ENV["YEAR"],
      country: ENV["COUNTRY"],
      funding_year: ENV["FUNDING_YEAR"],
      limit: limit,
      max_limit: max_limit,
      max_cost_usd: max_cost_usd,
      dry_run: dry_run,
      queue_proposals: queue_proposals,
      reviewer: ENV["REVIEWER"],
      notes: ENV["NOTES"]
    )

    puts "Created company discovery run_id=#{run.id} discovery_type=#{discovery_type} status=#{run.status}"
    puts "Dry run: #{run.details['dry_run']}"
    puts "Mode: #{run.details['mode']}"
    puts "Summary: #{run.details['summary'].to_json}"
    puts "Candidates:"
    Array(run.details["candidates"]).each do |candidate|
      puts "- #{candidate['name']} (#{candidate['website']}) status=#{candidate['status']} verified=#{candidate['website_verified']}"
    end
    puts "Proposal results: #{Array(run.details['proposal_results']).to_json}" if Array(run.details["proposal_results"]).any?
  end
end
